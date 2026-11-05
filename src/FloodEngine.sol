// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITicketFlood {
    function sink(uint256 tokenId) external;
    function floodSnap(uint256 tokenId) external view returns (bool alive, uint8 cabin);
    function totalMinted() external view returns (uint256);
    function aliveCount() external view returns (uint256);
}

interface ISandbagView {
    function consumeProtection(uint256 tokenId, uint256 dayIndex) external returns (bool protected);
    function protectedUntil(uint256 tokenId, uint256 dayIndex) external view returns (bool);
}

interface ISaleOpenView {
    function opened() external view returns (bool);
    function openedAt() external view returns (uint256);
}

interface IArkPotLand {
    function land() external;
}

/// @title FloodEngine — nightly flood with two-step future-block randomness.
/// @notice Day boundary: 21:00 Asia/Shanghai = 13:00 UTC. Anyone may commit / settleBatch.
/// @notice Water: days 1–7 soft 2–3%; days 8–100: 3–8%. A ticket with no settled cabin is exposed
///         (same pool as economy, the most vulnerable class). Sandbags are the only skip.
/// @notice Settlement is batched. `dayState.settled` stays false until the mint snapshot is fully
///         counted and the chosen set is sunk. One batch never walks more than `MAX_BATCH` ids.
contract FloodEngine {
    uint256 public constant DAY0_OFFSET = 13 hours; // 21:00 CST = 13:00 UTC
    uint256 public constant COMMIT_DELAY = 5; // blocks
    uint256 public constant MAX_DAYS = 100;
    /// @notice Hard cap so one `settleBatch` stays under the BSC per-tx gas limit at 10_000 tickets.
    uint256 public constant MAX_BATCH = 400;

    uint8 internal constant PHASE_COUNT = 1;
    uint8 internal constant PHASE_PLAN = 2;
    uint8 internal constant PHASE_SINK = 3;
    uint8 internal constant PHASE_DONE = 4;

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
        uint8 waterBps; // percent points: days 1–7 soft 2..3; days 8–100: 3..8
        uint32 sunkCount;
    }

    /// @dev phase 1 counts exposure, 2 plans the exact sink set, 3 sinks, 4 done.
    ///      `seed` is fixed when the run begins so later batches do not need the commit blockhash.
    struct SettleProgress {
        uint32 nextId;
        uint32 exposed;
        uint32 toSink;
        uint32 cursor;
        uint32 mintedSnap;
        uint8 phase;
        uint256 seed;
    }

    mapping(uint256 => DayState) public dayState; // dayIndex 1..100
    mapping(uint256 => SettleProgress) public settleProgress;

    // day => word => bits. Ticket ids that are exposed, then exposed-ordinals chosen to sink.
    mapping(uint256 => mapping(uint256 => uint256)) private _exposed;
    mapping(uint256 => mapping(uint256 => uint256)) private _sinkAt;

    event Wired(address nft, address shop, address pot, address sale);
    event Started(uint256 genesisDay);
    event Commit(uint256 indexed dayIndex, uint64 commitBlock);
    event SettleBatch(uint256 indexed dayIndex, uint8 phase, uint32 nextId, uint32 exposed, uint32 sunk);
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

    /// @notice Cabin requests close once night 100 can be committed, and once that night has settled.
    ///         Pending tickets are already exposed, so a draw after the last night cannot dodge it.
    function requestsClosed() public view returns (bool) {
        if (!started) return false;
        if (dayState[MAX_DAYS].settled) return true;
        return _dayIndex(block.timestamp) >= genesisDay + MAX_DAYS;
    }

    /// @notice First word of `dayState`, for callers that only need the commit block.
    function commitBlockOf(uint256 dayIndex) external view returns (uint64) {
        return dayState[dayIndex].commitBlock;
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

    /// @notice Re-commit if the commit blockhash expired before settlement started.
    function recommit(uint256 dayIndex) external {
        require(started, "not started");
        require(dayIndex >= 1 && dayIndex <= MAX_DAYS, "day");
        DayState storage st = dayState[dayIndex];
        require(st.commitBlock != 0 && !st.settled, "bad");
        require(settleProgress[dayIndex].phase == 0, "processing");
        require(block.number > st.commitBlock + 256, "not expired");
        st.commitBlock = uint64(block.number + COMMIT_DELAY);
        emit Commit(dayIndex, st.commitBlock);
    }

    /// @notice Walk up to `maxCount` ticket ids (capped at `MAX_BATCH`). Repeat until settled.
    /// @dev The candidate list from v1 is gone: an empty list used to settle the night with zero sinks.
    ///      Count freezes the exposed set (alive, not sandbagged; pending cabins included). Plan picks
    ///      `ceil(exposed * water / 100)` ids with the same Fisher-Yates as v1, at least 1 when anyone
    ///      is exposed. Sink applies that set. The day is not final until both passes finish.
    function settleBatch(uint256 dayIndex, uint256 maxCount) external {
        require(started, "not started");
        require(dayIndex >= 1 && dayIndex <= MAX_DAYS, "day");
        require(maxCount > 0, "count");
        if (maxCount > MAX_BATCH) maxCount = MAX_BATCH;

        DayState storage st = dayState[dayIndex];
        require(!st.settled, "settled");
        SettleProgress storage sp = settleProgress[dayIndex];

        if (sp.phase == 0) _begin(st, sp, dayIndex);

        if (sp.phase == PHASE_COUNT) {
            _count(sp, dayIndex, maxCount);
            if (sp.nextId > sp.mintedSnap) sp.phase = PHASE_PLAN;
            emit SettleBatch(dayIndex, sp.phase, sp.nextId, sp.exposed, st.sunkCount);
            return;
        }

        if (sp.phase == PHASE_PLAN) {
            _plan(st, sp, dayIndex);
            if (sp.toSink == 0) {
                _finish(st, sp, dayIndex);
                return;
            }
            sp.phase = PHASE_SINK;
            sp.nextId = 1;
            sp.cursor = 0;
            emit SettleBatch(dayIndex, sp.phase, sp.nextId, sp.exposed, st.sunkCount);
            return;
        }

        _sink(st, sp, dayIndex, maxCount);
        if (sp.nextId > sp.mintedSnap) _finish(st, sp, dayIndex);
        else emit SettleBatch(dayIndex, sp.phase, sp.nextId, sp.exposed, st.sunkCount);
    }

    function _begin(DayState storage st, SettleProgress storage sp, uint256 dayIndex) internal {
        require(st.commitBlock != 0, "bad");
        require(block.number > st.commitBlock, "too early");
        require(block.number <= st.commitBlock + 256, "expired");
        bytes32 h = blockhash(st.commitBlock);
        require(h != bytes32(0), "no hash");

        uint256 seed = uint256(keccak256(abi.encodePacked(h, dayIndex, address(this))));
        // Soft flood week 1 so most unprotected tickets can survive toward ~7d economy payback.
        // Days 1–7: 2..3% inclusive (2 + seed%2). Days 8–100: legacy 3..8% (3 + seed%6).
        uint8 waterPct = dayIndex <= 7 ? uint8(2 + (seed % 2)) : uint8(3 + (seed % 6));
        st.waterBps = waterPct;
        sp.seed = seed;
        sp.phase = PHASE_COUNT;
        sp.nextId = 1;
        sp.mintedSnap = uint32(ticketNft.totalMinted());
    }

    function _count(SettleProgress storage sp, uint256 dayIndex, uint256 maxCount) internal {
        uint256 id = sp.nextId;
        uint256 end = id + maxCount;
        uint256 snap = sp.mintedSnap;
        if (end > snap + 1) end = snap + 1;
        uint256 exposed = sp.exposed;
        for (; id < end; ++id) {
            (bool alive,) = ticketNft.floodSnap(id);
            if (!alive) continue;
            if (sandbagShop.protectedUntil(id, dayIndex)) continue;
            _set(_exposed, dayIndex, id);
            unchecked {
                exposed += 1;
            }
        }
        sp.exposed = uint32(exposed);
        sp.nextId = uint32(id);
    }

    function _plan(DayState storage st, SettleProgress storage sp, uint256 dayIndex) internal {
        uint256 nExp = sp.exposed;
        uint256 toSink;
        if (nExp > 0) {
            // Ceil. A handful of exposed tickets must not round the night down to zero sinks.
            toSink = (nExp * uint256(st.waterBps) + 99) / 100;
            if (toSink > nExp) toSink = nExp;
        }
        sp.toSink = uint32(toSink);
        if (toSink == 0) return;

        uint256 seed = sp.seed;
        uint256[] memory perm = new uint256[](nExp);
        for (uint256 i; i < nExp; ++i) perm[i] = i;
        for (uint256 i; i < toSink; ++i) {
            uint256 j = i + (uint256(keccak256(abi.encodePacked(seed, i))) % (nExp - i));
            (perm[i], perm[j]) = (perm[j], perm[i]);
            _set(_sinkAt, dayIndex, perm[i]);
        }
    }

    function _sink(DayState storage st, SettleProgress storage sp, uint256 dayIndex, uint256 maxCount) internal {
        uint256 id = sp.nextId;
        uint256 end = id + maxCount;
        uint256 snap = sp.mintedSnap;
        if (end > snap + 1) end = snap + 1;
        uint256 ordinal = sp.cursor;
        uint32 sunk = st.sunkCount;
        for (; id < end; ++id) {
            if (!_get(_exposed, dayIndex, id)) {
                // Not in the frozen exposed set (sunk already, or sandbagged at count time).
                sandbagShop.consumeProtection(id, dayIndex);
                continue;
            }
            if (_get(_sinkAt, dayIndex, ordinal)) {
                ticketNft.sink(id);
                unchecked {
                    sunk += 1;
                }
            }
            unchecked {
                ordinal += 1;
            }
        }
        st.sunkCount = sunk;
        sp.cursor = uint32(ordinal);
        sp.nextId = uint32(id);
    }

    function _finish(DayState storage st, SettleProgress storage sp, uint256 dayIndex) internal {
        st.settled = true;
        sp.phase = PHASE_DONE;
        emit Settled(dayIndex, st.waterBps, st.sunkCount, ticketNft.aliveCount());
        emit SettleBatch(dayIndex, PHASE_DONE, sp.nextId, sp.exposed, st.sunkCount);
        if (dayIndex == MAX_DAYS) emit LandfallRequested();
    }

    /// @notice After day 100 is fully settled, anyone locks the pot. The pot reads the live survivor
    ///         counter. Callers do not pass an id list, so a partial list cannot set the share.
    function landfall() external {
        require(dayState[MAX_DAYS].settled, "not day100");
        pot.land();
    }

    function _get(mapping(uint256 => mapping(uint256 => uint256)) storage bits, uint256 day, uint256 id)
        internal
        view
        returns (bool)
    {
        return (bits[day][id >> 8] & (uint256(1) << (id & 255))) != 0;
    }

    function _set(mapping(uint256 => mapping(uint256 => uint256)) storage bits, uint256 day, uint256 id) internal {
        bits[day][id >> 8] |= uint256(1) << (id & 255);
    }
}
