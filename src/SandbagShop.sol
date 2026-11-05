// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IArkBurn {
    function burnFrom(address from, uint256 amount) external;
}

interface ITicketOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
    function aliveCount() external view returns (uint256);
    function isAlive(uint256 tokenId) external view returns (bool);
    function markYield(uint256 tokenId) external;
}

interface IFloodCommit {
    function sale() external view returns (address);
    function commitBlockOf(uint256 dayIndex) external view returns (uint64);
}

interface ISaleOpenedShop {
    function opened() external view returns (bool);
}

/// @title SandbagShop — burn ARK for 1-night flood protection; giftable.
contract SandbagShop {
    uint256 public constant BASE_PRICE = 50 ether; // 50 ARK at full survivors
    uint256 public constant REF_ALIVE = 10_000;

    IArkBurn public immutable ark;
    ITicketOwner public immutable tickets;
    address public immutable floodEngine;

    // tokenId => dayIndex => protected
    mapping(uint256 => mapping(uint256 => bool)) public protectedUntil;
    // unused sandbags held by address (giftable)
    mapping(address => uint256) public bags;

    event Bought(address indexed buyer, uint256 count, uint256 priceEach, uint256 burned);
    event Gifted(address indexed from, address indexed to, uint256 indexed tokenId, uint256 dayIndex);
    event Applied(address indexed user, uint256 indexed tokenId, uint256 dayIndex);
    event Consumed(uint256 indexed tokenId, uint256 dayIndex);

    constructor(address ark_, address tickets_, address floodEngine_) {
        require(ark_ != address(0) && tickets_ != address(0) && floodEngine_ != address(0), "zero");
        ark = IArkBurn(ark_);
        tickets = ITicketOwner(tickets_);
        floodEngine = floodEngine_;
    }

    function price() public view returns (uint256) {
        uint256 alive = tickets.aliveCount();
        if (alive == 0) alive = 1;
        // rises as survivors drop: BASE * REF / alive
        return (BASE_PRICE * REF_ALIVE) / alive;
    }

    function buy(uint256 count) external {
        require(count > 0, "count");
        uint256 each = price();
        uint256 total = each * count;
        ark.burnFrom(msg.sender, total);
        bags[msg.sender] += count;
        emit Bought(msg.sender, count, each, total);
    }

    /// @notice Apply one bag to protect `tokenId` for `dayIndex` (must own ticket).
    /// @dev Only after the pool is open, and only before that night's flood is committed.
    function applyBag(uint256 tokenId, uint256 dayIndex) external {
        require(tickets.ownerOf(tokenId) == msg.sender, "not owner");
        require(tickets.isAlive(tokenId), "dead");
        _useBag(tokenId, dayIndex);
        emit Applied(msg.sender, tokenId, dayIndex);
    }

    /// @notice Gift protection onto someone else's ticket for a day.
    /// @dev Same gates as `applyBag`. A gift before the pool opens cannot mark the ticket and
    ///      block its refund.
    function gift(uint256 tokenId, uint256 dayIndex) external {
        require(tickets.isAlive(tokenId), "dead");
        _useBag(tokenId, dayIndex);
        emit Gifted(msg.sender, tickets.ownerOf(tokenId), tokenId, dayIndex);
    }

    function _useBag(uint256 tokenId, uint256 dayIndex) internal {
        require(dayIndex >= 1 && dayIndex <= 100, "day");
        require(ISaleOpenedShop(IFloodCommit(floodEngine).sale()).opened(), "not open");
        require(IFloodCommit(floodEngine).commitBlockOf(dayIndex) == 0, "committed");
        require(bags[msg.sender] > 0, "no bag");
        require(!protectedUntil[tokenId][dayIndex], "already");
        bags[msg.sender] -= 1;
        protectedUntil[tokenId][dayIndex] = true;
        tickets.markYield(tokenId);
    }

    /// @notice FloodEngine consumes protection flag for the night.
    function consumeProtection(uint256 tokenId, uint256 dayIndex) external returns (bool) {
        require(msg.sender == floodEngine, "not flood");
        bool p = protectedUntil[tokenId][dayIndex];
        if (p) {
            protectedUntil[tokenId][dayIndex] = false;
            emit Consumed(tokenId, dayIndex);
        }
        return p;
    }
}
