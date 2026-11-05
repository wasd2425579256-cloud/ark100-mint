// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ARK — production / tax token for ARK100.
/// @notice Hard-coded 2% buy/sell tax vs the official pair:
///         burn 0.5% + pot 0.5% (ARK sent to `taxPot`) + team 1%.
///         Wallet-to-wallet transfers are untaxed. Sale, ticket production, and the sandbag shop are exempt
///         so pool seeding, post-open zaps, and claims are not taxed twice.
/// @dev No adjustable tax, no blacklist, no pause, no upgradeable proxy. `HARD_CAP` limits circulating
///      supply (balance of the dead address is excluded), so burns free headroom for later production mints.
contract ArkToken is ERC20 {
    uint256 public constant HARD_CAP = 2_000_000_000 ether;
    uint256 public constant TAX_BPS = 200; // 2%
    uint256 public constant BURN_BPS = 50; // 0.5%
    uint256 public constant POT_BPS = 50; // 0.5%
    uint256 public constant TEAM_BPS = 100; // 1%
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @dev PancakeSwap V2 on BSC. The genesis pair address is CREATE2-predictable, so transfers into it
    ///      can be rejected before the sale adds the first liquidity. Init-code hash checked against
    ///      the live WBNB/USDT pair 0x16b9a82891338f9bA80E2D6970Fdda79D1eb0daE.
    address public constant PANCAKE_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    bytes32 public constant PAIR_INIT_CODE_HASH = 0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;

    address public immutable deployer;
    address public immutable projectWallet;
    address public immutable taxPot; // receives ARK pot-leg of trade tax (immutable sink)
    address public immutable launchPair;

    address public sale; // ArkSale — pool seed minter + tax exempt
    address public ticketNft; // TicketNFT — production minter
    address public sandbagShop; // burn helper, tax exempt when burning via shop pull

    address public officialPair;
    uint256 public poolOpenBlock;

    event SaleSet(address sale);
    event TicketNftSet(address nft);
    event SandbagShopSet(address shop);
    event OfficialPairSet(address pair);
    event PoolOpenNotified(address pair, uint256 openBlock);
    event TradeTaxed(address indexed trader, bool isBuy, uint256 burnPart, uint256 potPart, uint256 teamPart);

    modifier onlyDeployer() {
        require(msg.sender == deployer, "not deployer");
        _;
    }

    constructor(address projectWallet_, address taxPot_) ERC20("ARK100", "ARK") {
        require(projectWallet_ != address(0) && taxPot_ != address(0), "zero");
        deployer = msg.sender;
        projectWallet = projectWallet_;
        taxPot = taxPot_;
        launchPair = _predictPair(address(this));
    }

    function setSale(address sale_) external onlyDeployer {
        require(sale == address(0) && sale_ != address(0), "sale set");
        sale = sale_;
        emit SaleSet(sale_);
    }

    function setTicketNft(address nft) external onlyDeployer {
        require(ticketNft == address(0) && nft != address(0), "nft set");
        ticketNft = nft;
        emit TicketNftSet(nft);
    }

    function setSandbagShop(address shop) external onlyDeployer {
        require(sandbagShop == address(0) && shop != address(0), "shop set");
        sandbagShop = shop;
        emit SandbagShopSet(shop);
    }

    function circulating() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD);
    }

    function headroom() public view returns (uint256) {
        return HARD_CAP - circulating();
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == sale || msg.sender == ticketNft, "not minter");
        require(circulating() + amount <= HARD_CAP, "cap");
        _mint(to, amount);
    }

    /// @notice Burn caller's tokens (SandbagShop uses burnFrom via allowance).
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        require(msg.sender == sandbagShop, "not shop");
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    function setOfficialPair(address pair) external {
        require(msg.sender == sale, "not sale");
        require(officialPair == address(0) && pair != address(0), "pair set");
        officialPair = pair;
        emit OfficialPairSet(pair);
    }

    function notifyPoolOpened(address pair) external {
        require(msg.sender == sale, "not sale");
        require(poolOpenBlock == 0, "opened");
        require(pair != address(0) && pair == officialPair, "bad pair");
        poolOpenBlock = block.number;
        emit PoolOpenNotified(pair, block.number);
    }

    function _predictPair(address token) internal pure returns (address) {
        (address token0, address token1) = token < WBNB ? (token, WBNB) : (WBNB, token);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        return
            address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", PANCAKE_FACTORY, salt, PAIR_INIT_CODE_HASH)))));
    }

    function _update(address from, address to, uint256 value) internal override {
        // mint / burn path
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        // Before the sale seeds the pair, nobody but the sale may send ARK into the predicted Pancake pair.
        // Otherwise a holder can set a skewed opening price and the genesis add (min amounts = full size)
        // either donates into that price or reverts and bricks `openPool`.
        require(poolOpenBlock != 0 || to != launchPair || from == sale, "pair locked");
        // system exemptions (sale zaps, production claims, shop burns)
        if (
            from == sale || to == sale || from == ticketNft || to == ticketNft || from == sandbagShop
                || to == sandbagShop
        ) {
            super._update(from, to, value);
            return;
        }

        address pair = officialPair;
        if (pair == address(0)) {
            // Pre-open wallet transfers are untaxed. The launch pair itself is locked above.
            super._update(from, to, value);
            return;
        }

        bool isBuy = from == pair;
        bool isSell = to == pair;
        if (!isBuy && !isSell) {
            super._update(from, to, value);
            return;
        }

        uint256 burnPart = (value * BURN_BPS) / 10_000;
        uint256 potPart = (value * POT_BPS) / 10_000;
        uint256 teamPart = (value * TEAM_BPS) / 10_000;
        uint256 sendPart = value - burnPart - potPart - teamPart;

        if (burnPart > 0) super._update(from, DEAD, burnPart);
        if (potPart > 0) super._update(from, taxPot, potPart);
        if (teamPart > 0) super._update(from, projectWallet, teamPart);
        if (sendPart > 0) super._update(from, to, sendPart);

        emit TradeTaxed(isBuy ? to : from, isBuy, burnPart, potPart, teamPart);
    }
}
