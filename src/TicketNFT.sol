// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IArkMinter {
    function mint(address to, uint256 amount) external;
}

interface IArkShopView {
    function sandbagShop() external view returns (address);
}

interface IFloodGate {
    function requestsClosed() external view returns (bool);
}

interface ISaleOpened {
    function opened() external view returns (bool);
}

/// @title TicketNFT — Gen0 ark tickets (ERC721).
/// @notice Cabins assigned via future-block settle. Sunk tickets produce 0.
/// No Ownable. Sale address set once by deployer.
contract TicketNFT is ERC721, ReentrancyGuard {
    uint8 public constant CABIN_PENDING = 0;
    uint8 public constant CABIN_ECONOMY = 1; // 70% — 100 ARK/day
    uint8 public constant CABIN_BUSINESS = 2; // 25% — 200 ARK/day
    uint8 public constant CABIN_CAPTAIN = 3; // 5% — 600 ARK/day
    uint8 public constant CABIN_SUNK = 4;

    uint256 public constant RATE_ECONOMY = 100 ether;
    uint256 public constant RATE_BUSINESS = 200 ether;
    uint256 public constant RATE_CAPTAIN = 600 ether;
    uint256 public constant CABIN_DELAY = 5; // blocks after request
    uint256 public constant DAY = 1 days;

    address public immutable deployer;
    address public sale;
    address public floodEngine;
    IArkMinter public arkToken;

    uint256 public totalMinted;
    uint256 public aliveCount;
    /// @notice Tickets with a settled cabin (economy, business, or captain) that have not sunk.
    ///         Pending cabins are alive but are not survivors. ArkPot reads this in `land`.
    uint256 public survivorCount;

    struct Ticket {
        uint8 cabin; // 0 pending, 1-3 live, 4 sunk
        uint64 lastClaim;
        uint64 mintedAt;
        address minter;
        uint64 cabinCommitBlock; // 0 = not requested / settled
    }

    mapping(uint256 => Ticket) public tickets;
    mapping(address => uint256) public mintedBy; // slots used
    /// @notice True after this ticket was paid cabin yield, or had a sandbag applied.
    mapping(uint256 => bool) public yieldClaimed;

    event SaleSet(address sale);
    event FloodEngineSet(address flood);
    event ArkTokenSet(address token);
    event TicketMinted(uint256 indexed tokenId, address indexed to, address indexed minter);
    event CabinRequested(uint256 indexed tokenId, uint64 commitBlock);
    event CabinSettled(uint256 indexed tokenId, uint8 cabin);
    event Sunk(uint256 indexed tokenId, address indexed owner);
    event TicketRetired(uint256 indexed tokenId, address indexed holder);
    event Claimed(uint256 indexed tokenId, address indexed to, uint256 amount);

    modifier onlySale() {
        require(msg.sender == sale, "not sale");
        _;
    }

    modifier onlyFlood() {
        require(msg.sender == floodEngine, "not flood");
        _;
    }

    constructor() ERC721("ARK100 Ticket", "ARKTIX") {
        deployer = msg.sender;
    }

    function setSale(address sale_) external {
        require(msg.sender == deployer, "not deployer");
        require(sale == address(0) && sale_ != address(0), "sale set");
        sale = sale_;
        emit SaleSet(sale_);
    }

    function setFloodEngine(address flood) external {
        require(msg.sender == deployer, "not deployer");
        require(floodEngine == address(0) && flood != address(0), "flood set");
        floodEngine = flood;
        emit FloodEngineSet(flood);
    }

    function setArkToken(address token) external {
        require(msg.sender == deployer, "not deployer");
        require(address(arkToken) == address(0) && token != address(0), "token set");
        arkToken = IArkMinter(token);
        emit ArkTokenSet(token);
    }

    function mintTo(address to, address minter) external onlySale returns (uint256 tokenId) {
        tokenId = ++totalMinted;
        tickets[tokenId] = Ticket({
            cabin: CABIN_PENDING,
            lastClaim: uint64(block.timestamp),
            mintedAt: uint64(block.timestamp),
            minter: minter,
            cabinCommitBlock: 0
        });
        mintedBy[minter] += 1;
        aliveCount += 1;
        _safeMint(to, tokenId);
        emit TicketMinted(tokenId, to, minter);
    }

    /// @notice Free a mint slot when a ticket sinks (returns quota to original minter).
    function sink(uint256 tokenId) external onlyFlood {
        Ticket storage t = tickets[tokenId];
        require(t.cabin != CABIN_SUNK && t.mintedAt != 0, "bad");
        if (_isSurvivorCabin(t.cabin)) survivorCount -= 1;
        // settle pending accrued as zero going forward; cabin becomes sunk
        t.cabin = CABIN_SUNK;
        t.lastClaim = uint64(block.timestamp);
        if (aliveCount > 0) aliveCount -= 1;
        if (mintedBy[t.minter] > 0) mintedBy[t.minter] -= 1;
        emit Sunk(tokenId, ownerOf(tokenId));
    }

    /// @notice Sale refund. Burns the ticket and marks it sunk. Does not return `mintedBy` quota.
    function retire(uint256 tokenId) external onlySale {
        Ticket storage t = tickets[tokenId];
        require(t.mintedAt != 0 && t.cabin != CABIN_SUNK, "bad");
        address holder = ownerOf(tokenId);
        if (_isSurvivorCabin(t.cabin)) survivorCount -= 1;
        t.cabin = CABIN_SUNK;
        t.cabinCommitBlock = 0;
        t.lastClaim = uint64(block.timestamp);
        if (aliveCount > 0) aliveCount -= 1;
        _burn(tokenId);
        emit TicketRetired(tokenId, holder);
    }

    function isSurvivor(uint256 tokenId) external view returns (bool) {
        Ticket storage t = tickets[tokenId];
        return t.mintedAt != 0 && t.cabin != CABIN_SUNK && t.cabin != CABIN_PENDING;
    }

    function isAlive(uint256 tokenId) public view returns (bool) {
        Ticket storage t = tickets[tokenId];
        return t.mintedAt != 0 && t.cabin != CABIN_SUNK;
    }

    function requestCabin(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "not owner");
        Ticket storage t = tickets[tokenId];
        require(t.cabin == CABIN_PENDING, "not pending");
        require(t.cabinCommitBlock == 0, "requested");
        // Once night 100 can start, a new draw would land after the floods that pending tickets
        // already had to face. In-flight requests can still be settled.
        if (floodEngine != address(0)) require(!IFloodGate(floodEngine).requestsClosed(), "flood closed");
        t.cabinCommitBlock = uint64(block.number + CABIN_DELAY);
        emit CabinRequested(tokenId, t.cabinCommitBlock);
    }

    /// @notice Anyone may settle. A live commit uses the future-block roll. An expired commit
    ///         (more than 256 blocks later) is economy, the worst class, and cannot be retried.
    function settleCabin(uint256 tokenId) external {
        Ticket storage t = tickets[tokenId];
        require(t.cabin == CABIN_PENDING, "not pending");
        require(t.cabinCommitBlock != 0, "no request");
        require(block.number > t.cabinCommitBlock, "too early");
        uint8 cabin;
        if (block.number > t.cabinCommitBlock + 256) {
            cabin = CABIN_ECONOMY;
        } else {
            bytes32 h = blockhash(t.cabinCommitBlock);
            require(h != bytes32(0), "no hash");
            uint256 roll = uint256(keccak256(abi.encodePacked(h, tokenId, address(this)))) % 100;
            if (roll < 70) cabin = CABIN_ECONOMY;
            else if (roll < 95) cabin = CABIN_BUSINESS;
            else cabin = CABIN_CAPTAIN;
        }
        t.cabin = cabin;
        t.cabinCommitBlock = 0;
        t.lastClaim = uint64(block.timestamp);
        survivorCount += 1;
        emit CabinSettled(tokenId, cabin);
    }

    function pendingArk(uint256 tokenId) public view returns (uint256) {
        Ticket storage t = tickets[tokenId];
        if (t.cabin == CABIN_PENDING || t.cabin == CABIN_SUNK || t.cabin == 0) return 0;
        uint256 rate = _rate(t.cabin);
        uint256 elapsed = block.timestamp - t.lastClaim;
        return (rate * elapsed) / DAY;
    }

    function claim(uint256 tokenId) external nonReentrant {
        require(ISaleOpened(sale).opened(), "not open");
        require(ownerOf(tokenId) == msg.sender, "not owner");
        Ticket storage t = tickets[tokenId];
        require(t.cabin >= CABIN_ECONOMY && t.cabin <= CABIN_CAPTAIN, "no cabin");
        uint256 amount = pendingArk(tokenId);
        require(amount > 0, "zero");
        t.lastClaim = uint64(block.timestamp);
        yieldClaimed[tokenId] = true;
        arkToken.mint(msg.sender, amount);
        emit Claimed(tokenId, msg.sender, amount);
    }

    /// @notice SandbagShop marks a ticket that received a bag. Pot and flood pay only after open.
    function markYield(uint256 tokenId) external {
        require(tickets[tokenId].mintedAt != 0, "bad");
        require(msg.sender == IArkShopView(address(arkToken)).sandbagShop(), "not reward");
        yieldClaimed[tokenId] = true;
    }

    function floodSnap(uint256 tokenId) external view returns (bool alive, uint8 cabin) {
        Ticket storage t = tickets[tokenId];
        cabin = t.cabin;
        alive = t.mintedAt != 0 && cabin != CABIN_SUNK;
    }

    function _isSurvivorCabin(uint8 cabin) internal pure returns (bool) {
        return cabin >= CABIN_ECONOMY && cabin <= CABIN_CAPTAIN;
    }

    function _rate(uint8 cabin) internal pure returns (uint256) {
        if (cabin == CABIN_ECONOMY) return RATE_ECONOMY;
        if (cabin == CABIN_BUSINESS) return RATE_BUSINESS;
        if (cabin == CABIN_CAPTAIN) return RATE_CAPTAIN;
        return 0;
    }

    /// @dev FloodEngine enumerates alive tickets off-chain / by id scan for v1.
    function cabinOf(uint256 tokenId) external view returns (uint8) {
        return tickets[tokenId].cabin;
    }
}
