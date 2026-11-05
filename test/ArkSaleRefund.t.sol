// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArkSale} from "../src/ArkSale.sol";
import {ArkToken} from "../src/ArkToken.sol";
import {ArkPot} from "../src/ArkPot.sol";
import {TicketNFT} from "../src/TicketNFT.sol";
import {FloodEngine} from "../src/FloodEngine.sol";
import {SandbagShop} from "../src/SandbagShop.sol";
import {TicketMarketBNB} from "../src/TicketMarketBNB.sol";
import {TicketBidMarket} from "../src/TicketBidMarket.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockAggregator} from "../src/mocks/MockAggregator.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";

/// @dev Sold is the third ArkSale variable after the reentrancy status word, the nft, and the token.
uint256 constant SOLD_SLOT = 3;

contract RefundFixture is Test {
    address team = makeAddr("team");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    MockAgentId agent;
    MockAggregator feed;
    MockWETH wbnb;
    MockRouter router;
    ArkPot pot;
    FloodEngine flood;
    TicketNFT tickets;
    ArkToken ark;
    ArkSale sale;
    SandbagShop shop;

    function setUp() public {
        agent = new MockAgentId();
        feed = new MockAggregator(700e8);
        wbnb = new MockWETH();
        router = new MockRouter(wbnb);
        pot = new ArkPot();
        flood = new FloodEngine();
        tickets = new TicketNFT();
        ark = new ArkToken(team, address(pot));
        sale = new ArkSale(team, address(pot), address(agent), address(feed), address(router));
        shop = new SandbagShop(address(ark), address(tickets), address(flood));

        pot.setSale(address(sale));
        pot.setFloodEngine(address(flood));
        tickets.setSale(address(sale));
        tickets.setFloodEngine(address(flood));
        tickets.setArkToken(address(ark));
        ark.setSale(address(sale));
        ark.setTicketNft(address(tickets));
        ark.setSandbagShop(address(shop));
        flood.wire(address(tickets), address(shop), address(pot), address(sale));
        sale.wire(address(tickets), address(ark));
        sale.startSale(block.timestamp);

        agent.setAllowed(alice, true, "alice.ai");
        agent.setAllowed(bob, true, "bob.ai");
        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
    }

    function _mint(address who, uint256 count) internal returns (uint256 due) {
        (due,) = sale.quoteMint(count);
        vm.prank(who);
        sale.mint{value: due}(count);
    }

    function _openWindow() internal {
        uint256 at = sale.startTime() + sale.REFUND_WINDOW();
        if (block.timestamp < at) vm.warp(at);
    }

    function _assertSolvent() internal view {
        uint256 minted = tickets.totalMinted();
        uint256 sumPaid;
        uint256 sumTeam;
        uint256 sumPot;
        uint256 live;
        for (uint256 id = 1; id <= minted; ++id) {
            uint256 paid = sale.paidBnb(id);
            if (paid == 0) continue;
            live += 1;
            uint256 teamCut = sale.teamShare(id);
            uint256 potCut = sale.potShare(id);
            assertLe(teamCut + potCut, paid, "ticket split");
            sumPaid += paid;
            sumTeam += teamCut;
            sumPot += potCut;
        }
        if (sale.opened()) {
            assertEq(sale.outstandingRefunds(), 0);
            assertEq(sale.teamDue(), 0);
            assertEq(sale.potDue(), 0);
            assertEq(sale.reserveBNB(), 0);
            return;
        }
        assertEq(sale.outstandingRefunds(), sumPaid, "outstanding");
        assertEq(sale.teamDue(), sumTeam, "team");
        assertEq(sale.potDue(), sumPot, "pot");
        assertEq(sale.reserveBNB(), sumPaid - sumTeam - sumPot, "reserve");
        assertEq(sale.teamDue() + sale.potDue() + sale.reserveBNB(), sale.outstandingRefunds(), "escrow");
        assertGe(address(sale).balance, sale.outstandingRefunds(), "solvent");
        assertGe(sale.sold(), live, "sold");
    }
}

contract ArkSaleRefundTest is RefundFixture {
    function test_refundBeforeWindow_reverts_andMintStillWorks() public {
        uint256 due = _mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(bytes("too early"));
        sale.refund(1);
        assertEq(sale.sold(), 1);
        assertEq(tickets.ownerOf(1), alice);

        _openWindow();
        uint256 bobDue = _mint(bob, 1);
        assertEq(sale.sold(), 2);
        assertGt(bobDue, 0);
        assertEq(sale.outstandingRefunds(), due + bobDue);
        _assertSolvent();
    }

    function test_holderRefunds_payerCannot_quotaStaysUsed() public {
        uint256 due = _mint(alice, 1);
        _openWindow();

        vm.prank(alice);
        tickets.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(bytes("not holder"));
        sale.refund(1);

        uint256 before = bob.balance;
        vm.prank(bob);
        sale.refund(1);
        assertEq(bob.balance - before, due);
        assertEq(sale.sold(), 0);
        assertEq(sale.outstandingRefunds(), 0);
        assertEq(address(sale).balance, 0);
        // Quota sticks to the original minter. The buyer who refunded did not spend a mint slot.
        assertEq(tickets.mintedBy(alice), 1);
        assertEq(tickets.mintedBy(bob), 0);
        vm.expectRevert();
        tickets.ownerOf(1);
        assertFalse(tickets.isAlive(1));
        assertEq(tickets.cabinOf(1), tickets.CABIN_SUNK());
        assertEq(tickets.aliveCount(), 0);

        // One slot stays consumed, so Alice can still mint the rest of her cap and no more.
        _mint(alice, 9);
        assertEq(tickets.mintedBy(alice), 10);
        (uint256 again,) = sale.quoteMint(1);
        vm.prank(alice);
        vm.expectRevert(bytes("max per addr"));
        sale.mint{value: again}(1);
        _mint(bob, 1);
        assertEq(tickets.mintedBy(bob), 1);
    }

    function test_refundDoesNotFreeMinterQuota() public {
        for (uint256 i; i < 10; ++i) {
            _mint(alice, 1);
        }
        _openWindow();
        for (uint256 id = 1; id <= 10; ++id) {
            vm.prank(alice);
            sale.refund(id);
        }
        assertEq(sale.sold(), 0);
        assertEq(tickets.mintedBy(alice), 10);
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        vm.expectRevert(bytes("max per addr"));
        sale.mint{value: due}(1);
        // A different wallet can take the freed live-supply slot.
        _mint(bob, 1);
        assertEq(sale.sold(), 1);
        _assertSolvent();
    }

    function test_twoTiers_partialRefund_thenOpenPaysRemainingEscrow() public {
        uint256 first = _mint(alice, 4);
        assertEq(sale.priceUsd(), 2 ether);
        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(uint256(2500)));
        assertEq(sale.priceUsd(), 3 ether);
        uint256 second = _mint(bob, 4);
        assertGt(second, first);
        _openWindow();

        uint256 refunded = sale.paidBnb(1) + sale.paidBnb(5);
        vm.prank(alice);
        sale.refund(1);
        vm.prank(bob);
        sale.refund(5);

        _assertSolvent();
        assertEq(sale.outstandingRefunds(), first + second - refunded);

        uint256 teamPay = sale.teamDue();
        uint256 potPay = sale.potDue();
        uint256 reservePay = sale.reserveBNB();
        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(sale.OPEN_AT()));
        uint256 teamBefore = team.balance;
        uint256 potBefore = address(pot).balance;
        sale.openPool();
        assertTrue(sale.opened());
        assertEq(team.balance - teamBefore, teamPay);
        assertEq(address(pot).balance - potBefore, potPay);
        assertGt(router.lp().balanceOf(sale.DEAD()), 0);
        assertEq(sale.outstandingRefunds(), 0);
        assertEq(sale.teamDue(), 0);
        assertEq(sale.reserveBNB(), 0);
        // Genesis LP took the reserve (and nothing else was donated).
        assertEq(address(sale).balance, 0);
        assertGt(reservePay, 0);

        vm.prank(alice);
        vm.expectRevert(bytes("opened"));
        sale.refund(2);
        _assertSolvent();
    }

    function test_autoOpen_countsLiveTickets() public {
        uint256 batch = _mint(alice, 10);
        _openWindow();
        uint256 paid = sale.paidBnb(1);
        vm.prank(alice);
        sale.refund(1);
        assertEq(sale.sold(), 9);
        assertEq(sale.outstandingRefunds(), batch - paid);

        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(uint256(2999)));
        address w = makeAddr("late");
        agent.setAllowed(w, true, "late.ai");
        vm.deal(w, 20 ether);
        uint256 teamBefore = sale.teamDue();
        uint256 potBefore = sale.potDue();
        (uint256 due,) = sale.quoteMint(1);
        uint256 teamPart = (due * sale.TEAM_BPS()) / 10_000;
        uint256 potPart = (due * sale.POT_BPS()) / 10_000;
        vm.prank(w);
        sale.mint{value: due}(1);
        assertTrue(sale.opened());
        assertEq(sale.sold(), 3000);
        assertEq(team.balance, teamBefore + teamPart);
        assertEq(address(pot).balance, potBefore + potPart);
        assertEq(sale.outstandingRefunds(), 0);
        _assertSolvent();
    }

    function test_listedTicketAndLiveBid_refundDoesNotTrapMarketFunds() public {
        _mint(alice, 2);
        _openWindow();

        TicketMarketBNB book = new TicketMarketBNB(address(tickets), team);
        vm.prank(alice);
        tickets.approve(address(book), 1);
        vm.prank(alice);
        book.list(1, 1 ether);
        assertTrue(book.listable(1));

        TicketBidMarket bids = new TicketBidMarket(address(tickets), team);
        uint8 anyKind = bids.KIND_ANY();
        vm.prank(bob);
        uint256 bidId = bids.postBid{value: 2 ether}(anyKind, 0, 1 ether, 2, 1 days);
        assertEq(address(bids).balance, 2 ether);

        uint256 paid = sale.paidBnb(1);
        uint256 before = alice.balance;
        vm.prank(alice);
        sale.refund(1);
        assertEq(alice.balance - before, paid);
        assertEq(address(book).balance, 0);
        assertEq(address(bids).balance, 2 ether);

        vm.prank(bob);
        vm.expectRevert();
        book.buy{value: 1 ether}(1);
        book.cleanListing(1);
        assertEq(book.listingCount(), 0);

        vm.prank(alice);
        tickets.approve(address(bids), 2);
        vm.prank(alice);
        bids.acceptBid(bidId, 2);
        (,, uint256 qtyLeft,,,,) = bids.bidOf(bidId);
        assertEq(qtyLeft, 1);
        assertEq(address(bids).balance, 1 ether);
        assertEq(tickets.ownerOf(2), bob);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        bids.cancelBid(bidId);
        assertEq(bob.balance - bobBefore, 1 ether);
        assertEq(address(bids).balance, 0);
        _assertSolvent();
    }

    function test_refundedTicket_unusableInCabinFloodAndShop() public {
        _mint(alice, 2);
        vm.prank(alice);
        tickets.requestCabin(1);
        vm.prank(alice);
        tickets.requestCabin(2);
        vm.roll(block.number + 6);
        tickets.settleCabin(1);
        tickets.settleCabin(2);
        assertTrue(tickets.isSurvivor(1));

        vm.prank(address(tickets));
        ark.mint(alice, 1_000_000 ether);
        uint256 px = shop.price();
        vm.prank(alice);
        ark.approve(address(shop), px);
        vm.prank(alice);
        shop.buy(1);

        _openWindow();
        vm.prank(alice);
        sale.refund(1);
        assertEq(tickets.aliveCount(), 1);
        assertFalse(tickets.isSurvivor(1));

        vm.expectRevert(bytes("not pending"));
        tickets.settleCabin(1);
        vm.prank(alice);
        vm.expectRevert();
        tickets.requestCabin(1);
        vm.prank(alice);
        vm.expectRevert(bytes("dead"));
        shop.gift(1, 1);
        vm.prank(alice);
        vm.expectRevert();
        shop.applyBag(1, 1);
        vm.prank(address(flood));
        vm.expectRevert(bytes("bad"));
        tickets.sink(1);

        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(sale.OPEN_AT()));
        sale.openPool();
        flood.start();
        vm.warp(block.timestamp + 2 days);
        flood.commit(1);
        vm.roll(block.number + 6);
        flood.settle(1, new uint256[](0));
        assertEq(tickets.cabinOf(1), tickets.CABIN_SUNK());
        vm.expectRevert();
        tickets.ownerOf(1);
        // The remaining ticket is still a real survivor and was not bricked by the burned id.
        assertTrue(tickets.isAlive(2));
    }

    function test_batchShares_sumExactly() public {
        for (uint256 n = 1; n <= 10; ++n) {
            address w = makeAddr(string(abi.encodePacked("batch", vm.toString(n))));
            agent.setAllowed(w, true, "batch.ai");
            vm.deal(w, 50 ether);
            uint256 beforePaid = sale.outstandingRefunds();
            uint256 due = _mint(w, n);
            assertEq(sale.outstandingRefunds(), beforePaid + due);
            _assertSolvent();
        }
        assertEq(sale.sold(), 55);
        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(uint256(2500)));
        assertEq(sale.priceUsd(), 3 ether);
        uint256 tierDue = _mint(bob, 7);
        assertEq(sale.priceUsd(), 3 ether);
        assertGt(tierDue, 0);
        _assertSolvent();
    }

    /// forge-config: default.fuzz.runs = 40
    function testFuzz_interleavedMintsAndRefunds(uint96 feedAnswer, uint256 salt) public {
        feed.setAnswer(int256(bound(feedAnswer, 80e8, 2_500e8)));
        for (uint256 step; step < 8; ++step) {
            uint256 roll = uint256(keccak256(abi.encode(salt, step)));
            if (roll % 3 == 0) _fuzzRefund(roll);
            else _fuzzMint(roll, step);
            _assertSolvent();
        }
    }

    function _fuzzMint(uint256 roll, uint256 step) internal {
        if (sale.opened()) return;
        uint256 count = (roll % 10) + 1;
        if (sale.sold() + count >= sale.OPEN_AT()) return;
        if (roll % 4 == 0 && sale.sold() < 2500 && 2500 + count < sale.OPEN_AT()) {
            vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(uint256(2500)));
        }
        address w = makeAddr(string(abi.encodePacked("fz", vm.toString(step), vm.toString(roll % 7))));
        agent.setAllowed(w, true, "fz.ai");
        vm.deal(w, 100 ether);
        if (tickets.mintedBy(w) + count > sale.MAX_PER_ADDRESS()) return;
        (uint256 due,) = sale.quoteMint(count);
        vm.prank(w);
        sale.mint{value: due}(count);
    }

    function _fuzzRefund(uint256 roll) internal {
        if (sale.opened()) return;
        uint256 minted = tickets.totalMinted();
        if (minted == 0) return;
        if (block.timestamp < sale.startTime() + sale.REFUND_WINDOW()) _openWindow();
        uint256 id = (roll % minted) + 1;
        if (sale.paidBnb(id) == 0) return;
        address holder = tickets.ownerOf(id);
        vm.prank(holder);
        sale.refund(id);
    }
}

/// @dev Interleaved mints and refunds at the $2 and $3 tiers. `sold` may be lifted to 2,500 so the
///      next mint prices at tier 1 without creating 2,500 real tickets; escrow still has to match
///      the tickets that were actually paid for. The handler never crosses OPEN_AT.
contract RefundSolvencyHandler is Test {
    ArkSale public sale;
    TicketNFT public tickets;
    MockAggregator public feed;
    address[] internal actors;

    function init(ArkSale sale_, TicketNFT tickets_, MockAggregator feed_, MockAgentId agent) external {
        sale = sale_;
        tickets = tickets_;
        feed = feed_;
        for (uint256 i; i < 6; ++i) {
            address w = address(uint160(0xA11CE + i));
            actors.push(w);
            agent.setAllowed(w, true, string(abi.encodePacked("h", vm.toString(i), ".ai")));
            vm.deal(w, 500 ether);
        }
    }

    function mint(uint256 actorSeed, uint256 countSeed, uint256 salt) external {
        if (sale.opened()) return;
        uint256 count = (countSeed % 10) + 1;
        if (sale.sold() + count >= sale.OPEN_AT()) return;
        if (salt % 5 == 0 && sale.sold() < 2500 && 2500 + count < sale.OPEN_AT()) {
            vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(uint256(2500)));
        }
        if (sale.sold() + count >= sale.OPEN_AT()) return;
        if (salt % 3 == 0) feed.setAnswer(int256(80e8 + (salt % 2400) * 1e8));
        address actor = actors[actorSeed % actors.length];
        if (tickets.mintedBy(actor) + count > sale.MAX_PER_ADDRESS()) return;
        (uint256 due,) = sale.quoteMint(count);
        if (actor.balance < due) return;
        vm.prank(actor);
        try sale.mint{value: due}(count) {} catch {}
    }

    function refund(uint256 salt) external {
        if (sale.opened()) return;
        uint256 minted = tickets.totalMinted();
        if (minted == 0) return;
        if (block.timestamp < sale.startTime() + sale.REFUND_WINDOW()) {
            vm.warp(sale.startTime() + sale.REFUND_WINDOW());
        }
        uint256 id = (salt % minted) + 1;
        if (sale.paidBnb(id) == 0) return;
        try tickets.ownerOf(id) returns (address holder) {
            vm.prank(holder);
            try sale.refund(id) {} catch {}
        } catch {}
    }
}

/// forge-config: default.invariant.runs = 30
/// forge-config: default.invariant.depth = 20
/// forge-config: default.invariant.fail_on_revert = false
contract ArkSaleRefundInvariantTest is Test {
    ArkSale sale;
    TicketNFT tickets;
    RefundSolvencyHandler handler;

    function setUp() public {
        address team = makeAddr("team");
        MockAgentId agent = new MockAgentId();
        MockAggregator feed = new MockAggregator(700e8);
        MockWETH wbnb = new MockWETH();
        MockRouter router = new MockRouter(wbnb);
        ArkPot pot = new ArkPot();
        FloodEngine flood = new FloodEngine();
        tickets = new TicketNFT();
        ArkToken ark = new ArkToken(team, address(pot));
        sale = new ArkSale(team, address(pot), address(agent), address(feed), address(router));
        SandbagShop shop = new SandbagShop(address(ark), address(tickets), address(flood));

        pot.setSale(address(sale));
        pot.setFloodEngine(address(flood));
        tickets.setSale(address(sale));
        tickets.setFloodEngine(address(flood));
        tickets.setArkToken(address(ark));
        ark.setSale(address(sale));
        ark.setTicketNft(address(tickets));
        ark.setSandbagShop(address(shop));
        flood.wire(address(tickets), address(shop), address(pot), address(sale));
        sale.wire(address(tickets), address(ark));
        sale.startSale(block.timestamp);

        handler = new RefundSolvencyHandler();
        handler.init(sale, tickets, feed, agent);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = RefundSolvencyHandler.mint.selector;
        selectors[1] = RefundSolvencyHandler.refund.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_refundEscrowSolvent() public view {
        uint256 minted = tickets.totalMinted();
        uint256 sumPaid;
        uint256 sumTeam;
        uint256 sumPot;
        uint256 live;
        for (uint256 id = 1; id <= minted; ++id) {
            uint256 paid = sale.paidBnb(id);
            if (paid == 0) continue;
            live += 1;
            uint256 teamCut = sale.teamShare(id);
            uint256 potCut = sale.potShare(id);
            assertLe(teamCut + potCut, paid);
            sumPaid += paid;
            sumTeam += teamCut;
            sumPot += potCut;
        }
        assertFalse(sale.opened());
        assertEq(sale.outstandingRefunds(), sumPaid);
        assertEq(sale.teamDue(), sumTeam);
        assertEq(sale.potDue(), sumPot);
        assertEq(sale.reserveBNB(), sumPaid - sumTeam - sumPot);
        assertGe(address(sale).balance, sumPaid);
        assertGe(sale.sold(), live);
        assertLt(sale.sold(), sale.OPEN_AT());
    }
}
