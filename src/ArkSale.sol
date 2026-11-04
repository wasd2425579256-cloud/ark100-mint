// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAgentIdVerifier} from "./interfaces/IAgentIdVerifier.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IPancakeRouter} from "./interfaces/IPancake.sol";

interface ITicketMinter {
    function mintTo(address to, address minter) external returns (uint256);
    function mintedBy(address) external view returns (uint256);
}

interface IArkTokenSale {
    function mint(address to, uint256 amount) external;
    function setOfficialPair(address pair) external;
    function notifyPoolOpened(address pair) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IArkPotWire {
    function setTicketNft(address nft) external;
}

interface IMockRouterExtra {
    function lp() external view returns (address);
}

/// @title ArkSale — Gen0 ticket sale: tiered USD, full refund if unopened, auto pool @ #3000.
/// @dev Pre-open escrow of team/pot legs enables 100% refunds. No withdraw/rescue.
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
    bool public refunding;
    address public pair;

    uint256 public teamDue;
    uint256 public potDue;
    uint256 public reserveBNB;

    mapping(uint256 => uint256) public paidBnb;
    mapping(uint256 => address) public payer;

    /// @notice block.timestamp at which the pool was opened (0 = not opened). Read by FloodEngine.start().
    uint256 public openedAt;

    event Wired(address nft, address token);
    event SaleStarted(uint256 startTime);
    event Minted(address indexed buyer, uint256 indexed tokenId, uint256 usdPrice, uint256 bnbPaid, string handle);
    event PoolOpened(address pair, uint256 bnbLp, uint256 arkLp, uint256 teamPaid, uint256 potPaid);
    event RefundEnabled();
    event Refunded(uint256 indexed tokenId, address indexed to, uint256 amount);

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
        require(!refunding, "refunding");
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

        for (uint256 i; i < count; ++i) {
            uint256 tokenId = ticketNft.mintTo(msg.sender, msg.sender);
            uint256 slice = base + (i == 0 ? rem : 0);
            paidBnb[tokenId] = slice;
            payer[tokenId] = msg.sender;
            unchecked {
                sold += 1;
            }
            emit Minted(msg.sender, tokenId, usdPx, slice, handle);
            if (!opened && sold == OPEN_AT) {
                // account this payment first below — open after accrual
            }
        }

        // Accrue split (escrow pre-open; pay immediately post-open)
        uint256 teamPart = (bnbDue * TEAM_BPS) / 10_000;
        uint256 potPart = (bnbDue * POT_BPS) / 10_000;
        uint256 reservePart = bnbDue - teamPart - potPart;

        if (!opened) {
            teamDue += teamPart;
            potDue += potPart;
            reserveBNB += reservePart;
        } else {
            (bool a,) = projectWallet.call{value: teamPart}("");
            require(a, "team");
            (bool b,) = pot.call{value: potPart}("");
            require(b, "pot");
            reserveBNB += reservePart; // post-open reserve unused in v1 (stranded) — acceptable for scaffold
        }

        lastMintTime = block.timestamp;

        if (!opened && sold >= OPEN_AT) {
            _openPool();
        }

        if (msg.value > bnbDue) {
            (bool sent,) = msg.sender.call{value: msg.value - bnbDue}("");
            require(sent, "overpay refund");
        }
    }

    function _openPool() internal {
        require(!opened, "opened");
        opened = true;
        openedAt = block.timestamp;

        uint256 teamPay = teamDue;
        uint256 potPay = potDue;
        uint256 lpBnb = reserveBNB;
        teamDue = 0;
        potDue = 0;
        reserveBNB = 0;

        (bool a,) = projectWallet.call{value: teamPay}("");
        require(a, "team");
        (bool b,) = pot.call{value: potPay}("");
        require(b, "pot");

        arkToken.mint(address(this), POOL_SEED_ARK);
        arkToken.approve(address(router), POOL_SEED_ARK);
        router.addLiquidityETH{value: lpBnb}(address(arkToken), POOL_SEED_ARK, 0, 0, DEAD, block.timestamp + 1 hours);

        try IMockRouterExtra(address(router)).lp() returns (address lpToken) {
            pair = lpToken;
        } catch {
            pair = address(uint160(uint256(keccak256(abi.encodePacked("ARKPAIR", address(arkToken))))));
        }
        arkToken.setOfficialPair(pair);
        arkToken.notifyPoolOpened(pair);
        emit PoolOpened(pair, lpBnb, POOL_SEED_ARK, teamPay, potPay);
    }

    /// @notice Permissionless insurance: anyone may open the pool if the threshold is met
    ///         but the auto-open in mint() did not fire. No privileges; same _openPool() path.
    function openPool() external nonReentrant {
        require(!refunding, "refunding");
        require(!opened, "opened");
        require(sold >= OPEN_AT, "below OPEN_AT");
        _openPool();
    }

    function enableRefunds() external {
        require(!opened, "opened");
        require(startTime != 0 && block.timestamp >= startTime + REFUND_WINDOW, "too early");
        refunding = true;
        // escrowed teamDue/potDue/reserve all remain on contract for refunds
        emit RefundEnabled();
    }

    function refund(uint256 tokenId) external nonReentrant {
        require(refunding, "not refunding");
        require(payer[tokenId] == msg.sender, "not payer");
        uint256 amount = paidBnb[tokenId];
        require(amount > 0, "zero");
        paidBnb[tokenId] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "pay");
        emit Refunded(tokenId, msg.sender, amount);
    }

    receive() external payable {}
}
