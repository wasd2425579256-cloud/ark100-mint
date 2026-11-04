// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITicketFlood {
    function sink(uint256 tokenId) external;
    function isAlive(uint256 tokenId) external view returns (bool);
    function cabinOf(uint256 tokenId) external view returns (uint8);
    function totalMinted() external view returns (uint256);
    function aliveCount() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ISandbagView {
    function consumeProtection(uint256 tokenId, uint256 dayIndex) external returns (bool protected);
}

interface ISaleOpenView {
    function opened() external view returns (bool);
    function openedAt() external view returns (uint256);
}

interface IArkPotLand {
    function land(uint256[] calldata survivorIds) external;
}

/// @title FloodEngine — nightly flood with two-step future-block randomness.
/// @notice Day boundary: 21:00 Asia/Shanghai = 13:00 UTC. Anyone may commit/settle.
contract FloodEngine {
    uint256 public constant DAY0_OFFSET = 13 hours; // 21:00 CST = 13:00 UTC
    uint256 public constant COMMIT_DELAY = 5; // blocks
    uint256 public constant MAX_DAYS = 100;
    uint8 public constant CABIN_SUNK = 4;

    address public immutable deployer;
    ITicketFlood public ticketNft;
    ISandbagView public sandbagShop;
    IArkPotLand public pot;
    address public sale;

    uint256 public genesisDay; // unix day index of first floodable day (set at pool open)
    bool public started;

    struct DayState {
        uint64 commitBlock; // block to read hash from
        bool settled;
        uint8 waterBps; // 300..800 meaning 3.00%..8.00%  (stored as 3..8 for simplicity)
        uint32 sunkCount;
    }

    mapping(uint256 => DayState) public dayState; // dayIndex 1..100

    event Wired(address nft, address shop, address pot, address sale);
    event Started(uint256 genesisDay);
    event Commit(uint256 indexed dayIndex, uint64 commitBlock);
    event Settled(uint256 indexed dayIndex, uint8 waterPct, uint32 sunk, uint256 aliveAfter);
    event LandfallRequested();

    constructor() {
        deployer = msg.sender;
    }

    function wire(address nft, address shop, address pot_, address sale_) external {
        require(msg.sender == deployer, "not deployer");
        require(address(ticketNft) == address(0), "wired");
        ticketNft = ITicketFlood(nft);
        sandbagShop = ISandbagView(shop);
        pot = IArkPotLand(pot_);
        sale = sale_;
        emit Wired(nft, shop, pot_, sale_);
    }

    /// @notice Called once after pool opens (by anyone). Genesis derives from sale.openedAt() —
    ///         no caller-supplied timestamp, so the flood calendar cannot be shifted.
    function start() external {
        require(!started, "started");
        require(address(ticketNft) != address(0), "no wire");
        uint256 poolOpenTimestamp = ISaleOpenView(sale).openedAt();
        require(ISaleOpenView(sale).opened() && poolOpenTimestamp != 0, "pool not open");
        started = true;
        // first flood day = calendar day of open in CST terms via UTC 13:00 buckets
        genesisDay = _dayIndex(poolOpenTimestamp);
        emit Started(genesisDay);
    }

    function _dayIndex(uint256 ts) internal pure returns (uint256) {
        // Shift so that day boundary is 13:00 UTC
        if (ts < DAY0_OFFSET) return 0;
        return (ts - DAY0_OFFSET) / 1 days;
    }

    function currentDayIndex() public view returns (uint256) {
        require(started, "not started");
        uint256 today = _dayIndex(block.timestamp);
        if (today <= genesisDay) return 1;
        uint256 d = today - genesisDay;
        if (d > MAX_DAYS) return MAX_DAYS;
        return d;
    }

    /// @notice Commit randomness for `dayIndex` after that day's 21:00 CST has passed.
    function commit(uint256 dayIndex) external {
        require(started, "not started");
        require(dayIndex >= 1 && dayIndex <= MAX_DAYS, "day");
        require(_dayIndex(block.timestamp) >= genesisDay + dayIndex, "too early");
        DayState storage st = dayState[dayIndex];
        require(!st.settled, "settled");
        require(st.commitBlock == 0, "committed");
        st.commitBlock = uint64(block.number + COMMIT_DELAY);
        emit Commit(dayIndex, st.commitBlock);
    }

    /// @notice Re-commit if previous commit blockhash expired.
    function recommit(uint256 dayIndex) external {
        DayState storage st = dayState[dayIndex];
        require(st.commitBlock != 0 && !st.settled, "bad");
        require(block.number > st.commitBlock + 256, "not expired");
        st.commitBlock = uint64(block.number + COMMIT_DELAY);
        emit Commit(dayIndex, st.commitBlock);
    }

    /// @notice Settle flood: sink unprotected tickets. `candidates` is caller-supplied alive ids.
    function settle(uint256 dayIndex, uint256[] calldata candidates) external {
        DayState storage st = dayState[dayIndex];
        require(st.commitBlock != 0 && !st.settled, "bad");
        require(block.number > st.commitBlock, "too early");
        require(block.number <= st.commitBlock + 256, "expired");
        bytes32 h = blockhash(st.commitBlock);
        require(h != bytes32(0), "no hash");

        uint256 seed = uint256(keccak256(abi.encodePacked(h, dayIndex, address(this))));
        uint8 waterPct = uint8(3 + (seed % 6)); // 3..8 inclusive
        st.waterBps = waterPct;

        // Filter alive & unprotected
        uint256 len = candidates.length;
        uint256[] memory exposed = new uint256[](len);
        uint256 nExp;
        for (uint256 i; i < len; ++i) {
            uint256 id = candidates[i];
            if (!ticketNft.isAlive(id)) continue;
            if (ticketNft.cabinOf(id) == 0) continue; // pending cabin skip
            bool protected_ = sandbagShop.consumeProtection(id, dayIndex);
            if (protected_) continue;
            exposed[nExp++] = id;
        }

        uint32 toSink = uint32((nExp * waterPct) / 100);
        // deterministic shuffle pick first toSink
        for (uint256 i; i < nExp && i < toSink; ++i) {
            uint256 j = i + (uint256(keccak256(abi.encodePacked(seed, i))) % (nExp - i));
            (exposed[i], exposed[j]) = (exposed[j], exposed[i]);
            ticketNft.sink(exposed[i]);
            st.sunkCount += 1;
        }

        st.settled = true;
        emit Settled(dayIndex, waterPct, st.sunkCount, ticketNft.aliveCount());

        if (dayIndex == MAX_DAYS) {
            emit LandfallRequested();
        }
    }

    /// @notice After day 100 settled, anyone passes survivor ids to lock the pot.
    function landfall(uint256[] calldata survivorIds) external {
        require(dayState[MAX_DAYS].settled, "not day100");
        pot.land(survivorIds);
    }
}
