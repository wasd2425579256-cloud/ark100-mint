// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAgentIdVerifier} from "./interfaces/IAgentIdVerifier.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IPancakeFactory, IPancakePair, IPancakeRouter, IWETH} from "./interfaces/IPancake.sol";
import {PancakeZap} from "./PancakeZap.sol";

interface ITicketMinter {
    function mintTo(address to, address minter) external returns (uint256);
    function mintedBy(address) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function retire(uint256 tokenId) external;
    function yieldClaimed(uint256 tokenId) external view returns (bool);
}

interface IArkTokenSale {
    function mint(address to, uint256 amount) external;
    function setOfficialPair(address pair) external;
    function notifyPoolOpened(address pair) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function launchPair() external view returns (address);
    function PANCAKE_FACTORY() external view returns (address);
    function WBNB() external view returns (address);
}

interface IArkPotWire {
    function setTicketNft(address nft) external;
}

/// @title ArkSale — Gen0 ticket sale: tiered USD, per-ticket refund until open, auto pool @ #3000.
/// @dev Pre-open, each ticket escrows its own 20/15/65 split (wei dust stays on that ticket's reserve
///      leg). After `startTime + REFUND_WINDOW`, while the pool is closed, the current holder may refund
///      that ticket. The refund burns it, returns `paidBnb`, and decrements `sold`. Minting continues.
///      The pool still opens at `OPEN_AT` live paid tickets. After open, refunds stop. There is no owner
///      and no withdraw/rescue of ticket funds. A refund does not free the minter's `MAX_PER_ADDRESS` slot.
///
///      Post-open, the same 20/15/65 split is paid immediately: 20% to `projectWallet`, 15% to the pot,
///      and 65% into `pendingLiqBNB`. That pending balance is zapped into the official PancakeSwap
///      ARK/WBNB pair (about half swapped for ARK, both sides added, LP sent to `DEAD`). No ARK is minted
///      for these adds — the genesis `POOL_SEED_ARK` mint is the only sale-side mint, same as v1.
///
///      Sandwich bound (permissionless zap):
///      - A reserve snapshot must be at least `QUOTE_MIN_DELAY` blocks old and at most `QUOTE_TTL` old.
///      - Execution reverts (and the snapshot is refreshed) if the live price has moved more than
///        `SLIPPAGE_BPS` from that snapshot. A same-block / atomic sandwich that moves the price past
///        the tolerance cannot fill.
///      - Each zap is capped at `LIQ_THRESHOLD`, so a filled sandwich is bounded by that size and by
///        the tolerance (about 2% of the swapped half), not by the whole remaining sale.
///      - Residual risk: someone who can hold a manipulated price for `QUOTE_MIN_DELAY` blocks against
///        arbitrage, then zap, does trade at the manipulated snapshot. The delay and the batch cap are
///        the cost of that attack. Funds are never pulled out to an attacker; a failed check just waits.
///      - Dust from the optimal-zap rounding stays in `pendingLiqBNB` and is included in the next zap.
///        After sell-out, a permissionless call may zap any positive remainder, so the tail does not sit
///        under `LIQ_MIN` forever. Sub-wei outputs that cannot clear the constant-product formula can
///        remain; they do not grow.
///
///      Raw BNB sent to this contract is not a mint. Before open it is folded into the genesis LP.
///      After open, `syncPending` / the next mint / `addLiquidity` adopts it into the zap balance.
///      It is not refundable. Direct transfers are not ticket escrow; there is still no rescue,
///      so do not send BNB directly.
contract ArkSale is ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant MAX_PER_ADDRESS = 10;
    uint256 public constant OPEN_AT = 3_000;
    uint256 public constant IDLE_DROP = 5 minutes;
    uint256 public constant REFUND_WINDOW = 7 days;
    uint256 public constant POT_BPS = 1_500;
    uint256 public constant TEAM_BPS = 2_000;
    uint256 public constant POOL_SEED_ARK = 1_500_000 ether; // ~7d economy payback at open (~$0.0028/ARK if LP≈$4225)
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @notice Auto-zap once pending BNB reaches this size. Also the per-call cap.
    uint256 public constant LIQ_THRESHOLD = 1 ether;
    /// @notice Smallest permissionless zap before sell-out. Below this, BNB waits for the next batch.
    uint256 public constant LIQ_MIN = 0.05 ether;
    /// @notice Max spot move versus the delayed reserve snapshot, in bps.
    uint256 public constant SLIPPAGE_BPS = 200;
    /// @notice Snapshot must be at least this many blocks old, so the quote is not from the zap's own block.
    uint256 public constant QUOTE_MIN_DELAY = 10;
    /// @notice Snapshot older than this is discarded and retaken.
    uint256 public constant QUOTE_TTL = 100;

    uint256 public constant PRICE_T0 = 2 ether;
    uint256 public constant PRICE_T1 = 3 ether;
    uint256 public constant PRICE_T2 = 4 ether;
    uint256 public constant PRICE_T3 = 5 ether;

    address public immutable deployer;
    address public immutable projectWallet;
    address public immutable pot;
    IAgentIdVerifier public immutable agentId;
    IAggregatorV3 public immutable bnbUsdFeed;
    IPancakeRouter public immutable router;

    ITicketMinter public ticketNft;
    IArkTokenSale public arkToken;

    uint256 public sold;
    uint256 public startTime;
    uint256 public lastMintTime;
    bool public opened;
    address public pair;

    uint256 public teamDue;
    uint256 public potDue;
    uint256 public reserveBNB;
    /// @notice Sum of ticket BNB still refundable. Equals teamDue + potDue + reserveBNB until open, then 0.
    uint256 public outstandingRefunds;
    /// @notice Post-open 65% (plus adopted donations and zap dust) waiting to be added to the pair.
    uint256 public pendingLiqBNB;

    /// @dev Reserve snapshot used as the zap's price reference. Not the live reserves.
    uint112 public quoteReserveBnb;
    uint112 public quoteReserveArk;
    uint64 public quoteBlock;

    mapping(uint256 => uint256) public paidBnb;
    mapping(uint256 => address) public payer;

    /// @notice block.timestamp at which the pool was opened (0 = not opened). Read by FloodEngine.start().
    uint256 public openedAt;

    event Wired(address nft, address token);
    event SaleStarted(uint256 startTime);
    event Minted(address indexed buyer, uint256 indexed tokenId, uint256 usdPrice, uint256 bnbPaid, string handle);
    event PoolOpened(address pair, uint256 bnbLp, uint256 arkLp, uint256 teamPaid, uint256 potPaid);
    event Refunded(uint256 indexed tokenId, address indexed to, uint256 amount);
    event LiqQuotePoked(uint112 reserveBnb, uint112 reserveArk, uint256 blockNumber);
    event LiquidityAdded(
        uint256 bnbIn, uint256 bnbSwapped, uint256 arkBought, uint256 leftoverBnb, uint256 leftoverArk
    );

    constructor(address projectWallet_, address pot_, address agentId_, address feed_, address router_) {
        require(
            projectWallet_ != address(0) && pot_ != address(0) && agentId_ != address(0) && feed_ != address(0)
                && router_ != address(0),
            "zero"
        );
        deployer = msg.sender;
        projectWallet = projectWallet_;
        pot = pot_;
        agentId = IAgentIdVerifier(agentId_);
        bnbUsdFeed = IAggregatorV3(feed_);
        router = IPancakeRouter(router_);
    }

    function wire(address nft, address token) external {
        require(msg.sender == deployer, "not deployer");
        require(address(ticketNft) == address(0) && nft != address(0) && token != address(0), "wired");
        ticketNft = ITicketMinter(nft);
        arkToken = IArkTokenSale(token);
        IArkPotWire(pot).setTicketNft(nft);
        emit Wired(nft, token);
    }

    function startSale(uint256 startTime_) external {
        require(msg.sender == deployer, "not deployer");
        require(startTime == 0, "started");
        require(address(ticketNft) != address(0), "no wire");
        if (startTime_ == 0) startTime_ = block.timestamp;
        startTime = startTime_;
        lastMintTime = startTime_;
        emit SaleStarted(startTime_);
    }

    function bnbUsd() public view returns (uint256) {
        require(bnbUsdFeed.decimals() == 8, "decimals");
        (, int256 answer,, uint256 updatedAt,) = bnbUsdFeed.latestRoundData();
        require(answer > 0 && updatedAt != 0, "bad price");
        require(block.timestamp >= updatedAt && block.timestamp - updatedAt < 1 days, "stale");
        return uint256(answer) * 1e10;
    }

    function _tierForSold(uint256 s) internal pure returns (uint256) {
        uint256 nextId = s + 1;
        if (nextId <= 2500) return 0;
        if (nextId <= 5000) return 1;
        if (nextId <= 7500) return 2;
        return 3;
    }

    function currentTier() public view returns (uint256) {
        uint256 fromSold = _tierForSold(sold);
        if (startTime == 0 || lastMintTime == 0) return fromSold;
        uint256 drops = (block.timestamp - lastMintTime) / IDLE_DROP;
        if (drops >= fromSold) return 0;
        return fromSold - drops;
    }

    function priceUsd() public view returns (uint256) {
        uint256 t = currentTier();
        if (t == 0) return PRICE_T0;
        if (t == 1) return PRICE_T1;
        if (t == 2) return PRICE_T2;
        return PRICE_T3;
    }

    function quoteMint(uint256 count) public view returns (uint256 bnbDue, uint256 usdTotal) {
        require(count > 0 && count <= MAX_PER_ADDRESS, "count");
        usdTotal = priceUsd() * count;
        bnbDue = (usdTotal * 1e18) / bnbUsd();
    }

    function mint(uint256 count) external payable nonReentrant {
        require(startTime != 0 && block.timestamp >= startTime, "not started");
        require(sold + count <= MAX_SUPPLY, "sold out");
        require(ticketNft.mintedBy(msg.sender) + count <= MAX_PER_ADDRESS, "max per addr");

        (bool ok, string memory handle) = agentId.verify(msg.sender);
        require(ok, "no agent id");

        (uint256 bnbDue,) = quoteMint(count);
        require(msg.value >= bnbDue, "underpay");

        uint256 usdPx = priceUsd();
        uint256 base = bnbDue / count;
        uint256 rem = bnbDue % count;
        bool preOpen = !opened;

        for (uint256 i; i < count; ++i) {
            uint256 tokenId = ticketNft.mintTo(msg.sender, msg.sender);
            uint256 slice = base + (i == 0 ? rem : 0);
            paidBnb[tokenId] = slice;
            payer[tokenId] = msg.sender;
            unchecked {
                sold += 1;
            }
            if (preOpen) {
                (uint256 teamPart, uint256 potPart, uint256 reservePart) = _legs(slice);
                teamDue += teamPart;
                potDue += potPart;
                reserveBNB += reservePart;
            }
            emit Minted(msg.sender, tokenId, usdPx, slice, handle);
        }

        // Split the quoted payment only. Overpay is returned before any of it can be treated as a donation.
        uint256 over = msg.value - bnbDue;
        if (over > 0) {
            (bool sent,) = msg.sender.call{value: over}("");
            require(sent, "overpay refund");
        }

        if (preOpen) {
            outstandingRefunds += bnbDue;
            if (sold >= OPEN_AT) _openPool();
        } else {
            (uint256 teamPart, uint256 potPart,) = _legs(bnbDue);
            _pay(projectWallet, teamPart, "team");
            _pay(pot, potPart, "pot");
            pendingLiqBNB = address(this).balance;
            _maybeZapFromMint();
        }

        lastMintTime = block.timestamp;
    }

    /// @dev Per-ticket pre-open, and per quoted batch after open. The reserve leg keeps the wei dust
    ///      so the three legs always sum to `amount`.
    function _legs(uint256 amount) internal pure returns (uint256 teamPart, uint256 potPart, uint256 reservePart) {
        teamPart = (amount * TEAM_BPS) / 10_000;
        potPart = (amount * POT_BPS) / 10_000;
        reservePart = amount - teamPart - potPart;
    }

    function _openPool() internal {
        require(!opened, "opened");

        uint256 teamPay = teamDue;
        uint256 potPay = potDue;
        uint256 reservePay = reserveBNB;
        require(outstandingRefunds == teamPay + potPay + reservePay, "escrow");

        opened = true;
        openedAt = block.timestamp;
        teamDue = 0;
        potDue = 0;
        reserveBNB = 0;
        outstandingRefunds = 0;

        _pay(projectWallet, teamPay, "team");
        _pay(pot, potPay, "pot");

        // Whatever remains is the 65% reserve plus any direct transfers. Both go to the genesis LP
        // so neither is left on the contract. Ticket overpay was already refunded.
        uint256 lpBnb = address(this).balance;
        require(lpBnb >= reservePay && lpBnb > 0, "no lp");
        _seedPair(lpBnb, teamPay, potPay);
        pendingLiqBNB = address(this).balance;
    }

    /// @dev Seed by transferring WBNB and ARK straight to the pair and calling `mint(DEAD)`.
    ///      An empty pair takes both amounts and sets the price. A pair that already exists
    ///      (created early, donated to, synced) must not revert the open:
    ///      - unsynced donations are skimmed to `DEAD` before we price the add;
    ///      - a synced donation with no LP yet is left in the pair (it cannot be pulled) and our
    ///        full amounts are minted on top, so the open still succeeds;
    ///      - if LP already exists, amounts are quoted to the live reserves so `mint` does not
    ///        revert, leftover ARK is sent to `DEAD`, and leftover BNB stays for the post-open zap.
    ///      ARK itself cannot be transferred into the predicted pair by anyone but the sale until
    ///      `notifyPoolOpened`, so a third party cannot set a two-sided price before this call.
    function _seedPair(uint256 lpBnb, uint256 teamPay, uint256 potPay) internal {
        arkToken.mint(address(this), POOL_SEED_ARK);
        address lpToken = _ensurePair();
        IPancakePair p = IPancakePair(lpToken);
        p.skim(DEAD);

        (uint256 bnbIn, uint256 arkIn) = _seedQuote(p, lpBnb, POOL_SEED_ARK);
        _pushWbnb(lpToken, bnbIn);
        require(arkToken.transfer(lpToken, arkIn), "ark");
        uint256 liquidity = p.mint(DEAD);
        require(liquidity > 0, "lp");
        p.skim(DEAD);

        uint256 leftoverArk = arkToken.balanceOf(address(this));
        if (leftoverArk > 0) require(arkToken.transfer(DEAD, leftoverArk), "ark dust");

        pair = lpToken;
        arkToken.setOfficialPair(lpToken);
        arkToken.notifyPoolOpened(lpToken);
        emit PoolOpened(lpToken, bnbIn, arkIn, teamPay, potPay);
    }

    function _seedQuote(IPancakePair p, uint256 bnbBal, uint256 arkBal)
        internal
        returns (uint256 bnbIn, uint256 arkIn)
    {
        bnbIn = bnbBal;
        arkIn = arkBal;
        uint256 supply = p.totalSupply();
        (uint256 reserveBnb, uint256 reserveArk) = _reservesOf(p);

        // Broken pair: LP exists but one reserve is 0, so `mint` would divide by zero.
        // Top up the empty side by 1 wei and sync, then quote against the repaired reserves.
        if (supply > 0 && (reserveBnb == 0 || reserveArk == 0)) {
            if (reserveArk == 0 && arkIn > 1) {
                require(arkToken.transfer(address(p), 1), "ark");
                arkIn -= 1;
            }
            if (reserveBnb == 0 && bnbIn > 1) {
                _pushWbnb(address(p), 1);
                bnbIn -= 1;
            }
            p.sync();
            (reserveBnb, reserveArk) = _reservesOf(p);
            supply = p.totalSupply();
        }

        // No LP yet (the grief: createPair + WBNB + sync). Deposit both full amounts.
        if (supply == 0 || reserveBnb == 0 || reserveArk == 0) return (bnbIn, arkIn);

        uint256 bnbOptimal = (arkIn * reserveBnb) / reserveArk;
        if (bnbOptimal <= bnbIn) {
            bnbIn = bnbOptimal == 0 ? 1 : bnbOptimal;
        } else {
            uint256 arkOptimal = (bnbIn * reserveArk) / reserveBnb;
            arkIn = arkOptimal == 0 ? 1 : arkOptimal;
        }
    }

    function _reservesOf(IPancakePair p) internal view returns (uint256 reserveBnb, uint256 reserveArk) {
        (uint112 r0, uint112 r1,) = p.getReserves();
        if (p.token0() == router.WETH()) return (uint256(r0), uint256(r1));
        return (uint256(r1), uint256(r0));
    }

    function _pushWbnb(address to, uint256 amount) internal {
        if (amount == 0) return;
        IWETH w = IWETH(router.WETH());
        w.deposit{value: amount}();
        require(w.transfer(to, amount), "wbnb");
    }

    function _ensurePair() internal returns (address lpToken) {
        address factory_ = router.factory();
        address wbnb = router.WETH();
        lpToken = IPancakeFactory(factory_).getPair(address(arkToken), wbnb);
        if (lpToken == address(0)) {
            lpToken = IPancakeFactory(factory_).createPair(address(arkToken), wbnb);
        }
        // On BSC the router factory is Pancake V2, so the pair must be the token's predicted address.
        // Tests use a mock factory; the token still locks its real predicted pair.
        if (factory_ == arkToken.PANCAKE_FACTORY()) {
            require(wbnb == arkToken.WBNB(), "wbnb");
            require(lpToken == arkToken.launchPair(), "pair mismatch");
        }
    }

    /// @notice Permissionless insurance: anyone may open the pool if the threshold is met
    ///         but the auto-open in mint() did not fire. No privileges; same `_openPool` path.
    function openPool() external nonReentrant {
        require(!opened, "opened");
        require(sold >= OPEN_AT, "below OPEN_AT");
        _openPool();
    }

    /// @notice Current holder refunds one ticket after the window, while the pool is closed.
    /// @dev Tickets can transfer and be listed before open. The markets do not escrow the NFT
    ///      (the seller only approves), and bids escrow BNB rather than the ticket. Burning makes
    ///      `ownerOf` revert, so `buy` and `acceptBid` revert before taking payment. `cleanListing`
    ///      still drops the stale row. Bid BNB stays until cancel or expiry. `retire` marks the
    ///      ticket sunk, so cabin, flood, shop, and the pot skip it, and mint quota is not returned.
    ///      Cabin `claim` and an applied sandbag set `yieldClaimed` and block the refund. The pot and
    ///      the flood pay nothing until the pool is open, which already closes refunds.
    function refund(uint256 tokenId) external nonReentrant {
        require(!opened, "opened");
        require(startTime != 0 && block.timestamp >= startTime + REFUND_WINDOW, "too early");
        require(ticketNft.ownerOf(tokenId) == msg.sender, "not holder");
        require(!ticketNft.yieldClaimed(tokenId), "yield claimed");
        uint256 amount = paidBnb[tokenId];
        require(amount > 0, "zero");
        (uint256 teamPart, uint256 potPart, uint256 reservePart) = _legs(amount);
        paidBnb[tokenId] = 0;
        teamDue -= teamPart;
        potDue -= potPart;
        reserveBNB -= reservePart;
        outstandingRefunds -= amount;
        sold -= 1;
        ticketNft.retire(tokenId);
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "pay");
        emit Refunded(tokenId, msg.sender, amount);
    }

    /// @notice Adopt direct BNB transfers into the post-open zap balance.
    function syncPending() external nonReentrant {
        require(opened, "closed");
        pendingLiqBNB = address(this).balance;
    }

    /// @notice Permissionless zap of post-open BNB into the official pair. LP tokens go to `DEAD`.
    /// @dev If the reserve snapshot is missing, expired, or the spot has moved past `SLIPPAGE_BPS`,
    ///      this refreshes the snapshot and returns false. The BNB stays here. A snapshot younger than
    ///      `QUOTE_MIN_DELAY` reverts so the caller does not accidentally reset it.
    ///      Before sell-out the amount must be at least `LIQ_MIN`. After sell-out any positive balance
    ///      can be flushed. Each call zaps at most `LIQ_THRESHOLD`.
    function addLiquidity() external nonReentrant returns (bool zapped) {
        require(opened, "closed");
        pendingLiqBNB = address(this).balance;
        uint256 bal = pendingLiqBNB;
        require(bal >= LIQ_MIN || (sold == MAX_SUPPLY && bal > 0), "below min");
        uint256 amount = bal > LIQ_THRESHOLD ? LIQ_THRESHOLD : bal;
        if (_quoteUsable() && _slippageOk(amount)) {
            _zap(amount);
            return true;
        }
        if (quoteBlock != 0 && block.number >= quoteBlock && block.number - quoteBlock < QUOTE_MIN_DELAY) {
            revert("quote delay");
        }
        _poke();
        return false;
    }

    function _maybeZapFromMint() internal {
        uint256 bal = address(this).balance;
        if (bal >= LIQ_THRESHOLD) {
            uint256 amount = LIQ_THRESHOLD;
            if (_quoteUsable() && _slippageOk(amount)) {
                _zap(amount);
                return;
            }
            // Keep a snapshot that is still inside the delay window; taking a new one would reset it.
            if (!(quoteBlock != 0 && block.number >= quoteBlock && block.number - quoteBlock < QUOTE_MIN_DELAY)) {
                if (quoteBlock != block.number) _poke();
            }
        } else if (quoteBlock == 0 || block.number > quoteBlock + QUOTE_TTL) {
            _poke();
        }
        pendingLiqBNB = address(this).balance;
    }

    function _quoteUsable() internal view returns (bool) {
        if (quoteBlock == 0 || block.number <= quoteBlock) return false;
        uint256 age = block.number - quoteBlock;
        return age >= QUOTE_MIN_DELAY && age <= QUOTE_TTL;
    }

    function _poke() internal {
        (uint256 liveBnb, uint256 liveArk) = _reserves();
        require(liveBnb > 0 && liveArk > 0, "reserves");
        require(liveBnb <= type(uint112).max && liveArk <= type(uint112).max, "reserves");
        quoteReserveBnb = uint112(liveBnb);
        quoteReserveArk = uint112(liveArk);
        quoteBlock = uint64(block.number);
        emit LiqQuotePoked(quoteReserveBnb, quoteReserveArk, block.number);
    }

    /// @dev True when the live mid price is within tolerance of the snapshot and the zap's live output
    ///      still clears the snapshot's min-out. A same-block reserve read is not used as the reference.
    function _slippageOk(uint256 bnbAmount) internal view returns (bool) {
        if (quoteReserveBnb == 0 || quoteReserveArk == 0) return false;
        (uint256 liveBnb, uint256 liveArk) = _reserves();
        if (liveBnb == 0 || liveArk == 0) return false;
        uint256 liveCross = liveArk * uint256(quoteReserveBnb);
        uint256 quoteCross = uint256(quoteReserveArk) * liveBnb;
        uint256 diff = liveCross > quoteCross ? liveCross - quoteCross : quoteCross - liveCross;
        if (quoteCross == 0 || diff * 10_000 > SLIPPAGE_BPS * quoteCross) return false;

        uint256 swapAmt = PancakeZap.bnbToSwap(bnbAmount, liveBnb);
        if (swapAmt == 0) return false;
        uint256 quoted = PancakeZap.amountOut(swapAmt, quoteReserveBnb, quoteReserveArk);
        if (quoted == 0) return false;
        uint256 live = PancakeZap.amountOut(swapAmt, liveBnb, liveArk);
        return live * 10_000 >= quoted * (10_000 - SLIPPAGE_BPS);
    }

    function _zap(uint256 bnbAmount) internal {
        (uint256 liveBnb,) = _reserves();
        uint256 swapAmt = PancakeZap.bnbToSwap(bnbAmount, liveBnb);
        uint256 quoted = PancakeZap.amountOut(swapAmt, quoteReserveBnb, quoteReserveArk);
        uint256 minOut = quoted * (10_000 - SLIPPAGE_BPS) / 10_000;
        require(swapAmt > 0 && minOut > 0, "dust");

        uint256 arkBefore = arkToken.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(arkToken);
        router.swapExactETHForTokens{value: swapAmt}(minOut, path, address(this), block.timestamp);

        uint256 arkBal = arkToken.balanceOf(address(this));
        uint256 bought = arkBal - arkBefore;
        uint256 bnbLeft = bnbAmount - swapAmt;
        arkToken.approve(address(router), arkBal);
        // Swap min-out is the price check. The add sits in the same transaction, after that swap,
        // so a 1-wei floor only rejects an empty mint — it does not widen the sandwich bound.
        (,, uint256 liquidity) =
            router.addLiquidityETH{value: bnbLeft}(address(arkToken), arkBal, 1, 1, DEAD, block.timestamp);
        require(liquidity > 0, "lp");

        uint256 leftoverArk = arkToken.balanceOf(address(this));
        pendingLiqBNB = address(this).balance;
        emit LiquidityAdded(bnbAmount, swapAmt, bought, pendingLiqBNB, leftoverArk);
    }

    function _reserves() internal view returns (uint256 reserveBnb, uint256 reserveArk) {
        IPancakePair p = IPancakePair(pair);
        (uint112 r0, uint112 r1,) = p.getReserves();
        if (p.token0() == router.WETH()) return (uint256(r0), uint256(r1));
        return (uint256(r1), uint256(r0));
    }

    function _pay(address to, uint256 amount, string memory err) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        require(ok, err);
    }

    /// @dev Direct transfers are not mints. Post-open they sit until `syncPending`, the next mint,
    ///      or `addLiquidity` adopts `address(this).balance` into the zap. Pre-open they are folded
    ///      into the genesis LP inside `_openPool`.
    receive() external payable {}
}
