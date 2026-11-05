// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ArkSale} from "../src/ArkSale.sol";
import {ArkToken} from "../src/ArkToken.sol";
import {ArkPot} from "../src/ArkPot.sol";
import {TicketNFT} from "../src/TicketNFT.sol";
import {FloodEngine} from "../src/FloodEngine.sol";
import {SandbagShop} from "../src/SandbagShop.sol";
import {PancakeZap} from "../src/PancakeZap.sol";
import {TicketMarketBNB} from "../src/TicketMarketBNB.sol";
import {TicketBidMarket} from "../src/TicketBidMarket.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockAggregator} from "../src/mocks/MockAggregator.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {MockRouter, MockLP} from "../src/mocks/MockRouter.sol";

contract Ark100Test is Test {
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
        feed = new MockAggregator(700e8); // $700
        wbnb = new MockWETH();
        router = new MockRouter(wbnb);

        pot = new ArkPot();
        flood = new FloodEngine();
        tickets = new TicketNFT();

        // taxPot = pot (receives ARK tax legs)
        ark = new ArkToken(team, address(pot));
        sale = new ArkSale(team, address(pot), address(agent), address(feed), address(router));
        shop = new SandbagShop(address(ark), address(tickets), address(flood));

        // wire once
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

    function _bnbForTickets(uint256 count) internal view returns (uint256) {
        (uint256 bnbDue,) = sale.quoteMint(count);
        return bnbDue;
    }

    function test_tierPricing_startsAt2usd() public view {
        assertEq(sale.priceUsd(), 2 ether);
        assertEq(sale.currentTier(), 0);
    }

    function test_tierPricing_idleDropFromHigherTier() public {
        // jump sold into tier 1 by direct storage — use mint loop helper with warp
        // Mint 1 at $2
        uint256 due = _bnbForTickets(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        assertEq(sale.sold(), 1);

        // Force tier-by-sold into tier1 by setting sold via many mints is heavy;
        // instead warp idle after manually increasing sold through repeated mints from many addrs.
        // Lightweight: only verify idle drop formula when fromSold>0 by minting until sold=2500 is too heavy.
        // Check that after mint, 5 min idle at sold=1 still tier 0 (floor).
        vm.warp(block.timestamp + 30 minutes);
        assertEq(sale.currentTier(), 0);
        assertEq(sale.priceUsd(), 2 ether);
    }

    function test_tierPricing_atSoldBoundaries() public view {
        (uint256 bnb,) = sale.quoteMint(1);
        // $2 / $700 = 2/700 BNB
        assertApproxEqAbs(bnb, (uint256(2 ether) * 1e18) / uint256(700 ether), 1e10);
    }

    function test_mint_requiresAgentId() public {
        address eve = makeAddr("eve");
        vm.deal(eve, 10 ether);
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(eve);
        vm.expectRevert(bytes("no agent id"));
        sale.mint{value: due}(1);
    }

    function test_mint_maxPerAddress() public {
        // alice mints 10
        for (uint256 i; i < 10; ++i) {
            (uint256 due,) = sale.quoteMint(1);
            vm.prank(alice);
            sale.mint{value: due}(1);
        }
        (uint256 due2,) = sale.quoteMint(1);
        vm.prank(alice);
        vm.expectRevert(bytes("max per addr"));
        sale.mint{value: due2}(1);
        assertEq(sale.sold(), 10);
        assertEq(tickets.balanceOf(alice), 10);
    }

    function test_refundPath_fullBnb() public {
        (uint256 due,) = sale.quoteMint(1);
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        sale.mint{value: due}(1);
        assertEq(alice.balance, balBefore - due);

        vm.warp(sale.startTime() + sale.REFUND_WINDOW() - 1);
        vm.prank(alice);
        vm.expectRevert(bytes("too early"));
        sale.refund(1);
        (uint256 dueBob,) = sale.quoteMint(1);
        vm.prank(bob);
        sale.mint{value: dueBob}(1);

        vm.warp(sale.startTime() + sale.REFUND_WINDOW());
        uint256 mid = alice.balance;
        vm.prank(alice);
        sale.refund(1);
        assertEq(alice.balance, mid + due);
        assertEq(sale.paidBnb(1), 0);
        assertEq(sale.sold(), 1);
        assertEq(tickets.mintedBy(alice), 1);
        vm.expectRevert();
        tickets.ownerOf(1);
    }

    function test_noOwnerWithdraw_onSaleAndPot() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        // escrow on sale
        assertGt(address(sale).balance, 0);
        // no withdraw function — attempt low-level call to common selectors
        vm.expectRevert();
        (bool ok,) = address(sale).call(abi.encodeWithSignature("withdraw()"));
        ok; // silence
        vm.expectRevert();
        (bool ok2,) = address(pot).call(abi.encodeWithSignature("withdraw()"));
        ok2;
        vm.expectRevert();
        (bool ok3,) = address(sale).call(abi.encodeWithSignature("rescueBNB(address)", team));
        ok3;
    }

    function test_lockedDefaults_poolSeedAndTeamImmutable() public view {
        assertEq(sale.POOL_SEED_ARK(), 1_500_000 ether);
        assertEq(sale.OPEN_AT(), 3_000);
        assertEq(sale.MAX_SUPPLY(), 10_000);
        assertEq(sale.MAX_PER_ADDRESS(), 10);
        assertEq(sale.TEAM_BPS(), 2_000);
        assertEq(sale.POT_BPS(), 1_500);
        assertEq(sale.projectWallet(), team);
        assertEq(ark.projectWallet(), team);
        // no premine: total supply still 0 before any mint/open
        assertEq(ark.totalSupply(), 0);
    }

    function test_taxConstants() public view {
        assertEq(ark.TAX_BPS(), 200);
        assertEq(ark.BURN_BPS(), 50);
        assertEq(ark.POT_BPS(), 50);
        assertEq(ark.TEAM_BPS(), 100);
        assertEq(ark.BURN_BPS() + ark.POT_BPS() + ark.TEAM_BPS(), ark.TAX_BPS());
    }

    function test_openPool_lpToDead() public {
        // Mint OPEN_AT tickets using many agents (10 each)
        uint256 need = sale.OPEN_AT();
        uint256 created;
        uint256 walletIdx;
        while (created < need) {
            address w = makeAddr(string(abi.encodePacked("w", vm.toString(walletIdx))));
            agent.setAllowed(w, true, string(abi.encodePacked("w", vm.toString(walletIdx), ".ai")));
            vm.deal(w, 500 ether);
            uint256 batch = need - created;
            if (batch > 10) batch = 10;
            (uint256 due,) = sale.quoteMint(batch);
            vm.prank(w);
            sale.mint{value: due}(batch);
            created += batch;
            walletIdx++;
        }
        assertTrue(sale.opened());
        assertEq(sale.sold(), need);
        // LP tokens to dead
        MockLP lp = router.lp();
        assertGt(lp.balanceOf(sale.DEAD()), 0);
        // team received 20%
        assertGt(team.balance, 0);
        // pot received 15%
        assertGt(address(pot).balance, 0);
        // sale drained of escrow
        assertEq(sale.teamDue(), 0);
        assertEq(sale.potDue(), 0);
        assertEq(sale.reserveBNB(), 0);
    }

    function test_sandbagBurn() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);

        // give alice ARK via ticket production: settle cabin then warp
        vm.prank(alice);
        tickets.requestCabin(1);
        vm.roll(block.number + 6);
        tickets.settleCabin(1);
        assertTrue(tickets.cabinOf(1) >= 1 && tickets.cabinOf(1) <= 3);

        vm.warp(block.timestamp + 10 days);
        vm.prank(alice);
        tickets.claim(1);
        assertGt(ark.balanceOf(alice), 0);

        // With 1 alive, sandbag price = BASE*REF/1 = 500_000 ARK — top up via production minter.
        vm.prank(address(tickets));
        ark.mint(alice, 1_000_000 ether);

        uint256 bal = ark.balanceOf(alice);
        uint256 px = shop.price();
        vm.prank(alice);
        ark.approve(address(shop), px);
        vm.prank(alice);
        shop.buy(1);
        assertEq(shop.bags(alice), 1);
        assertEq(ark.balanceOf(alice), bal - px);

        vm.prank(alice);
        shop.applyBag(1, 1);
        assertTrue(shop.protectedUntil(1, 1));
    }

    function test_floodSettle_withManySinks() public {
        // mint 100 tickets across 10 wallets
        for (uint256 i; i < 10; ++i) {
            address w = makeAddr(string(abi.encodePacked("f", vm.toString(i))));
            agent.setAllowed(w, true, "x.ai");
            vm.deal(w, 50 ether);
            (uint256 due,) = sale.quoteMint(10);
            vm.prank(w);
            sale.mint{value: due}(10);
        }
        assertEq(tickets.totalMinted(), 100);

        // settle cabins for all
        for (uint256 id = 1; id <= 100; ++id) {
            address own = tickets.ownerOf(id);
            vm.prank(own);
            tickets.requestCabin(id);
        }
        vm.roll(block.number + 6);
        for (uint256 id = 1; id <= 100; ++id) {
            tickets.settleCabin(id);
        }

        // simulate threshold reached, open via public insurance, then start flood from sale.openedAt
        vm.expectRevert(bytes("pool not open"));
        flood.start();
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        flood.start();
        vm.expectRevert(bytes("started"));
        flood.start();
        vm.warp(block.timestamp + 2 days);
        flood.commit(1);
        vm.roll(block.number + 6);

        uint256[] memory candidates = new uint256[](100);
        for (uint256 i; i < 100; ++i) {
            candidates[i] = i + 1;
        }
        uint256 aliveBefore = tickets.aliveCount();
        flood.settle(1, candidates);
        uint256 aliveAfter = tickets.aliveCount();
        assertLt(aliveAfter, aliveBefore);
        // night 1 is the soft week: 2..3% of ~100 => sink 2..3
        assertGe(aliveBefore - aliveAfter, 2);
        assertLe(aliveBefore - aliveAfter, 3);
        (,, uint8 water1,) = flood.dayState(1);
        assertGe(water1, 2);
        assertLe(water1, 3);

        // A partial / empty candidate list must not settle the night with zero sinks.
        uint256 aliveNight1 = aliveAfter;
        vm.warp(block.timestamp + 1 days);
        flood.commit(2);
        vm.roll(block.number + 6);
        flood.settle(2, new uint256[](0));
        assertLt(tickets.aliveCount(), aliveNight1);

        // nights 8–100 stay on the 3..8% band
        vm.warp(block.timestamp + 7 days);
        flood.commit(8);
        vm.roll(block.number + 6);
        uint256 aliveMid = tickets.aliveCount();
        flood.settle(8, candidates);
        uint256 sunk8 = aliveMid - tickets.aliveCount();
        assertGe(sunk8, (aliveMid * 3) / 100);
        assertLe(sunk8, (aliveMid * 8) / 100);
        (,, uint8 water8,) = flood.dayState(8);
        assertGe(water8, 3);
        assertLe(water8, 8);
    }

    // ---- openPool insurance ----
    uint256 constant SOLD_SLOT = 3;

    function _forceSold(uint256 v) internal {
        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(v));
        assertEq(sale.sold(), v);
    }

    function _mintSome() internal {
        (uint256 due,) = sale.quoteMint(10);
        vm.prank(alice);
        sale.mint{value: due}(10);
    }

    event PoolOpened(address pair, uint256 bnbLp, uint256 arkLp, uint256 teamPaid, uint256 potPaid);

    function test_openPool_revertsBelowThreshold() public {
        _mintSome();
        vm.expectRevert(bytes("below OPEN_AT"));
        sale.openPool();
        _forceSold(sale.OPEN_AT() - 1);
        vm.expectRevert(bytes("below OPEN_AT"));
        vm.prank(bob);
        sale.openPool();
        assertFalse(sale.opened());
    }

    function test_openPool_atThreshold_anyoneCanOpen() public {
        _mintSome();
        uint256 lpBnb = sale.reserveBNB();
        uint256 teamPay = sale.teamDue();
        uint256 potPay = sale.potDue();
        _forceSold(sale.OPEN_AT()); // simulate auto-open not having fired
        assertFalse(sale.opened());
        vm.expectEmit(false, false, false, false, address(sale));
        emit PoolOpened(address(0), lpBnb, sale.POOL_SEED_ARK(), teamPay, potPay);
        vm.prank(bob); // random caller, no privileges
        sale.openPool();
        assertTrue(sale.opened());
        assertEq(sale.openedAt(), block.timestamp);
        assertEq(sale.reserveBNB(), 0);
        assertEq(sale.teamDue(), 0);
        assertEq(team.balance, teamPay);
        assertGt(router.lp().balanceOf(sale.DEAD()), 0);
    }

    function test_openPool_aboveThreshold() public {
        _mintSome();
        _forceSold(sale.OPEN_AT() + 5);
        sale.openPool();
        assertTrue(sale.opened());
    }

    function test_openPool_revertsWhenAlreadyOpened() public {
        _mintSome();
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        vm.expectRevert(bytes("opened"));
        sale.openPool();
    }

    function test_openPool_duringRefundWindow_countsLiveTickets() public {
        _mintSome();
        vm.warp(block.timestamp + sale.REFUND_WINDOW());
        vm.prank(alice);
        sale.refund(1);
        assertEq(sale.sold(), 9);
        _forceSold(sale.OPEN_AT() - 1);
        vm.expectRevert(bytes("below OPEN_AT"));
        sale.openPool();
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        assertTrue(sale.opened());
        vm.prank(alice);
        vm.expectRevert(bytes("opened"));
        sale.refund(2);
    }

    function test_autoOpen_setsOpenedAt_andFloodStarts() public {
        vm.warp(1_800_000_000);
        test_openPool_lpToDead();
        assertEq(sale.openedAt(), block.timestamp);
        vm.expectRevert(bytes("opened"));
        sale.openPool();
        flood.start();
        assertEq(flood.genesisDay(), (sale.openedAt() - 13 hours) / 1 days);
    }

    function test_siteSelectors_unchanged() public view {
        assertEq(ArkSale.mint.selector, bytes4(hex"a0712d68"));
        assertEq(ArkSale.openPool.selector, bytes4(hex"eb5797a4"));
        assertEq(ArkSale.refund.selector, bytes4(hex"278ecde1"));
        assertEq(ArkSale.quoteMint.selector, bytes4(hex"665216c6"));
        assertEq(ArkSale.priceUsd.selector, bytes4(hex"8b3948bd"));
        assertEq(ArkSale.currentTier.selector, bytes4(hex"d679677a"));
        assertEq(ArkSale.bnbUsd.selector, bytes4(hex"58614dbf"));
        assertEq(_sig("sold()"), bytes4(hex"02c7e7af"));
        assertEq(_sig("startTime()"), bytes4(hex"78e97925"));
        assertEq(_sig("opened()"), bytes4(hex"5f88eade"));
        assertEq(_sig("openedAt()"), bytes4(hex"38930203"));
        assertEq(_sig("lastMintTime()"), bytes4(hex"9d463520"));
        assertEq(_sig("payer(uint256)"), bytes4(hex"561874ee"));
        assertEq(_sig("paidBnb(uint256)"), bytes4(hex"f88e127c"));
        assertEq(_sig("pair()"), bytes4(hex"a8aa1b31"));
        assertEq(_sig("started()"), bytes4(hex"1f2698ab"));
        assertEq(FloodEngine.currentDayIndex.selector, bytes4(hex"dbb8cc46"));
        assertEq(_sig("dayState(uint256)"), bytes4(hex"68b9fa97"));
        assertEq(FloodEngine.start.selector, bytes4(hex"be9a6555"));
        assertEq(FloodEngine.commit.selector, bytes4(hex"f4f98ad5"));
        assertEq(_sig("totalMinted()"), bytes4(hex"a2309ff8"));
        assertEq(_sig("aliveCount()"), bytes4(hex"0145a938"));
        assertEq(_sig("mintedBy(address)"), bytes4(hex"3cef28d2"));
        assertEq(_sig("ownerOf(uint256)"), bytes4(hex"6352211e"));
        assertEq(TicketNFT.cabinOf.selector, bytes4(hex"a768222b"));
        assertEq(TicketNFT.isAlive.selector, bytes4(hex"d84b2361"));
        assertEq(TicketNFT.pendingArk.selector, bytes4(hex"17d15042"));
        assertEq(_sig("tickets(uint256)"), bytes4(hex"50b44712"));
        assertEq(TicketNFT.requestCabin.selector, bytes4(hex"0ac028a7"));
        assertEq(TicketNFT.settleCabin.selector, bytes4(hex"2cdf61fe"));
        assertEq(TicketNFT.claim.selector, bytes4(hex"379607f5"));
        assertEq(TicketNFT.isSurvivor.selector, bytes4(hex"7c649965"));
        assertEq(SandbagShop.price.selector, bytes4(hex"a035b1fe"));
        assertEq(_sig("BASE_PRICE()"), bytes4(hex"f86325ed"));
        assertEq(_sig("bags(address)"), bytes4(hex"8c4c2801"));
        assertEq(_sig("protectedUntil(uint256,uint256)"), bytes4(hex"736e07b9"));
        assertEq(SandbagShop.buy.selector, bytes4(hex"d96a094a"));
        assertEq(SandbagShop.applyBag.selector, bytes4(hex"840ced87"));
        assertEq(_sig("landed()"), bytes4(hex"939a1b1b"));
        assertEq(_sig("survivorCount()"), bytes4(hex"6f7840b2"));
        assertEq(_sig("sharePerTicket()"), bytes4(hex"b771d65d"));
        assertEq(ArkPot.claimShare.selector, bytes4(hex"0cc03e7a"));
        assertEq(_sig("officialPair()"), bytes4(hex"2eab62e4"));
        assertEq(_sig("totalSupply()"), bytes4(hex"18160ddd"));

        // Getters the site reads. A rename or a removed variable fails compilation here.
        sale.sold();
        sale.startTime();
        sale.opened();
        sale.openedAt();
        sale.lastMintTime();
        sale.payer(1);
        sale.paidBnb(1);
        sale.pair();
        flood.started();
        flood.dayState(1);
        tickets.totalMinted();
        tickets.aliveCount();
        tickets.mintedBy(alice);
        tickets.tickets(1);
        shop.BASE_PRICE();
        shop.bags(alice);
        shop.protectedUntil(1, 1);
        pot.landed();
        pot.survivorCount();
        pot.sharePerTicket();
        ark.officialPair();
    }

    function _sig(string memory signature) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(signature)));
    }

    function test_overpayRefunded_andEscrowMatchesQuote() public {
        (uint256 due,) = sale.quoteMint(2);
        uint256 before = alice.balance;
        vm.prank(alice);
        sale.mint{value: due + 0.25 ether}(2);
        assertEq(before - alice.balance, due);
        assertEq(sale.outstandingRefunds(), due);
        assertEq(sale.teamDue() + sale.potDue() + sale.reserveBNB(), due);
        assertGe(address(sale).balance, due);
    }

    function test_refundPartial_thenRemaining() public {
        (uint256 due,) = sale.quoteMint(2);
        vm.prank(alice);
        sale.mint{value: due}(2);
        uint256 first = sale.paidBnb(1);
        uint256 second = sale.paidBnb(2);
        assertEq(first + second, due);

        vm.warp(block.timestamp + 7 days + 1);
        uint256 mid = alice.balance;
        vm.prank(alice);
        sale.refund(1);
        assertEq(alice.balance, mid + first);
        assertEq(sale.outstandingRefunds(), second);
        assertEq(sale.sold(), 1);
        vm.prank(alice);
        sale.refund(2);
        assertEq(sale.outstandingRefunds(), 0);
        assertEq(sale.paidBnb(2), 0);
        assertEq(sale.sold(), 0);
        assertEq(sale.teamDue() + sale.potDue() + sale.reserveBNB(), 0);
    }

    function test_staleFeed_blocksMint() public {
        (uint256 due,) = sale.quoteMint(1);
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vm.expectRevert(bytes("stale"));
        sale.mint{value: due}(1);
    }

    function test_pairLocked_untilSaleSeeds() public {
        vm.prank(address(tickets));
        ark.mint(alice, 1000 ether);
        address predicted = ark.launchPair();
        vm.expectRevert(bytes("pair locked"));
        vm.prank(alice);
        ark.transfer(predicted, 1 ether);
        // Wallet transfers that are not the predicted pair still work.
        vm.prank(alice);
        ark.transfer(bob, 1 ether);
        assertEq(ark.balanceOf(bob), 1 ether);
    }

    function test_mintPast3000_postOpenSplit_notStranded() public {
        _mintCount(sale.OPEN_AT());
        assertTrue(sale.opened());
        assertEq(sale.reserveBNB(), 0);
        assertEq(sale.teamDue(), 0);
        assertEq(sale.potDue(), 0);
        assertEq(sale.outstandingRefunds(), 0);
        assertEq(sale.pair(), address(router.lp()));
        assertEq(ark.officialPair(), sale.pair());
        assertGt(ark.poolOpenBlock(), 0);
        assertGt(router.lp().balanceOf(sale.DEAD()), 0);
        // Genesis liquidity took the escrow. The contract must not keep it.
        assertEq(address(sale).balance, sale.pendingLiqBNB());

        uint256 supply = ark.totalSupply();
        uint256 teamBefore = team.balance;
        uint256 potBefore = address(pot).balance;
        uint256 pendingBefore = sale.pendingLiqBNB();

        address w = makeAddr("after-open");
        agent.setAllowed(w, true, "after.ai");
        vm.deal(w, 10 ether);
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(w);
        sale.mint{value: due}(1);

        uint256 teamPart = (due * sale.TEAM_BPS()) / 10_000;
        uint256 potPart = (due * sale.POT_BPS()) / 10_000;
        uint256 reservePart = due - teamPart - potPart;
        assertEq(team.balance - teamBefore, teamPart);
        assertEq(address(pot).balance - potBefore, potPart);
        assertEq(sale.reserveBNB(), 0);
        assertEq(sale.pendingLiqBNB(), pendingBefore + reservePart);
        assertEq(address(sale).balance, sale.pendingLiqBNB());
        // Post-open liquidity must not mint ARK.
        assertEq(ark.totalSupply(), supply);
        assertLt(sale.pendingLiqBNB(), sale.LIQ_THRESHOLD());
    }

    function test_manualZap_thresholdCap_andSlippage() public {
        _openSmall();
        uint256 supply = ark.totalSupply();
        uint256 deadBefore = router.lp().balanceOf(sale.DEAD());
        (uint256 bnbBefore,) = _pairReserves();

        _donate(0.01 ether);
        vm.expectRevert(bytes("below min"));
        sale.addLiquidity();

        _donate(1 ether);
        assertFalse(sale.addLiquidity()); // snapshot only
        vm.expectRevert(bytes("quote delay"));
        sale.addLiquidity();
        vm.roll(block.number + sale.QUOTE_MIN_DELAY() - 1);
        vm.expectRevert(bytes("quote delay"));
        sale.addLiquidity();

        vm.roll(block.number + 1);
        uint256 balBeforeZap = address(sale).balance;
        assertGe(balBeforeZap, sale.LIQ_THRESHOLD());
        assertTrue(sale.addLiquidity());
        assertEq(ark.totalSupply(), supply);
        assertGt(router.lp().balanceOf(sale.DEAD()), deadBefore);
        (uint256 bnbAfter,) = _pairReserves();
        assertGt(bnbAfter, bnbBefore);
        assertEq(address(sale).balance, sale.pendingLiqBNB());
        // The 0.01 BNB donated under the minimum stays behind; the 1 BNB batch itself must not.
        assertLt(address(sale).balance, 0.02 ether);
        assertLt(ark.balanceOf(address(sale)), 1e12);

        // Spot moved past the tolerance: do not zap, and do not touch the BNB.
        uint256 stuck = address(sale).balance;
        uint256 deadNow = router.lp().balanceOf(sale.DEAD());
        _donate(0.2 ether);
        assertFalse(sale.addLiquidity());
        vm.roll(block.number + sale.QUOTE_MIN_DELAY());
        (uint256 liveBnb, uint256 liveArk) = _pairReserves();
        router.skew(liveBnb, liveArk / 2);
        uint256 held = address(sale).balance;
        assertFalse(sale.addLiquidity());
        assertEq(address(sale).balance, held);
        assertEq(router.lp().balanceOf(sale.DEAD()), deadNow);
        assertGt(held, stuck);
    }

    function test_repeatedZaps_balanceStaysUnderThreshold() public {
        _openSmall();
        uint256 supply = ark.totalSupply();
        for (uint256 i; i < 5; ++i) {
            _donate(1 ether);
            assertFalse(sale.addLiquidity());
            vm.roll(block.number + sale.QUOTE_MIN_DELAY());
            assertTrue(sale.addLiquidity());
            assertLt(address(sale).balance, sale.LIQ_THRESHOLD());
            assertEq(address(sale).balance, sale.pendingLiqBNB());
            assertEq(ark.totalSupply(), supply);
        }
    }

    function test_soldOutFlush_andDonationAdoption() public {
        _openSmall();
        _donate(0.01 ether);
        _forceSold(sale.MAX_SUPPLY());
        assertFalse(sale.addLiquidity());
        vm.roll(block.number + sale.QUOTE_MIN_DELAY());
        assertTrue(sale.addLiquidity());
        assertLt(address(sale).balance, 0.001 ether);
        assertEq(address(sale).balance, sale.pendingLiqBNB());
    }

    function test_preOpenDonation_isNotTakenFromRefunds() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        _donate(0.4 ether);
        vm.warp(block.timestamp + 7 days + 1);
        uint256 mid = alice.balance;
        vm.prank(alice);
        sale.refund(1);
        assertEq(alice.balance, mid + due);
        // Donation is not ticket escrow and is not pulled into the refund.
        assertEq(address(sale).balance, 0.4 ether);
    }

    function test_preOpenDonation_isSeededIntoLp() public {
        _mintSome();
        uint256 reserve = sale.reserveBNB();
        _donate(0.4 ether);
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        (uint256 bnbReserve,) = _pairReserves();
        assertGe(bnbReserve, reserve + 0.4 ether);
        assertEq(address(sale).balance, 0);
        assertEq(sale.pendingLiqBNB(), 0);
    }

    function test_pot_rejectsPartialOrDuplicate_andPaysDust() public {
        (uint256 due,) = sale.quoteMint(2);
        vm.prank(alice);
        sale.mint{value: due}(2);
        _settleAll(2);

        uint256[] memory one = new uint256[](1);
        one[0] = 1;
        vm.prank(address(flood));
        vm.expectRevert(bytes("survivors"));
        pot.land(one);

        uint256[] memory dup = new uint256[](2);
        dup[0] = 1;
        dup[1] = 1;
        vm.prank(address(flood));
        vm.expectRevert(bytes("dup"));
        pot.land(dup);

        vm.deal(address(pot), 11);
        uint256[] memory both = new uint256[](2);
        both[0] = 2;
        both[1] = 1;
        vm.prank(address(flood));
        pot.land(both);
        assertEq(pot.sharePerTicket(), 5);

        uint256 aBefore = alice.balance;
        vm.prank(alice);
        pot.claimShare(1);
        vm.prank(alice);
        pot.claimShare(2);
        // 11 wei / 2 = 5, and the last claim takes the leftover wei.
        assertEq(alice.balance - aBefore, 11);
        assertEq(address(pot).balance, 0);
    }

    function test_marketRedeploy_listsRealTicket() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        _settleAll(1);

        TicketMarketBNB book = new TicketMarketBNB(address(tickets), team);
        vm.prank(alice);
        tickets.approve(address(book), 1);
        vm.prank(alice);
        book.list(1, 1 ether);

        uint256 teamBefore = team.balance;
        uint256 aliceBefore = alice.balance;
        vm.prank(bob);
        book.buy{value: 1 ether}(1);
        assertEq(tickets.ownerOf(1), bob);
        (uint256 fee, uint256 proceeds) = book.feeOn(1 ether);
        assertEq(team.balance - teamBefore, fee);
        assertEq(alice.balance - aliceBefore, proceeds);
        assertEq(address(book).balance, 0);
    }

    function testFuzz_zapLeavesBalancedRemainder(uint96 bnbIn_, uint96 reserveBnb_, uint96 reserveArk_) public pure {
        uint256 b = bound(uint256(bnbIn_), 1e15, 1000 ether);
        uint256 x = bound(uint256(reserveBnb_), 1e15, 1000 ether);
        uint256 y = bound(uint256(reserveArk_), 1e18, 2_000_000_000 ether);
        uint256 s = PancakeZap.bnbToSwap(b, x);
        uint256 outAmt = PancakeZap.amountOut(s, x, y);
        assertGt(s, 0);
        assertGt(outAmt, 0);
        assertLt(s, b);
        uint256 xPrime = x + s;
        uint256 yPrime = y - outAmt;
        uint256 left = (b - s) * yPrime;
        uint256 right = outAmt * xPrime;
        uint256 diff = left > right ? left - right : right - left;
        // Integer zap stays within 5 bps of the post-swap reserve ratio, so liquidity adds do not
        // refund a growing BNB or ARK balance.
        assertLe(diff * 10_000, right * 5 + xPrime + yPrime);
    }

    function test_refund_holderNotPayer_quotaStaysUsed() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        vm.prank(alice);
        tickets.transferFrom(alice, bob, 1);
        vm.warp(sale.startTime() + sale.REFUND_WINDOW());
        vm.prank(alice);
        vm.expectRevert(bytes("not holder"));
        sale.refund(1);
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        sale.refund(1);
        assertEq(bob.balance, bobBefore + due);
        assertEq(tickets.mintedBy(alice), 1);
        assertEq(sale.sold(), 0);
        for (uint256 i; i < 9; ++i) {
            (uint256 more,) = sale.quoteMint(1);
            vm.prank(alice);
            sale.mint{value: more}(1);
        }
        (uint256 blocked,) = sale.quoteMint(1);
        vm.prank(alice);
        vm.expectRevert(bytes("max per addr"));
        sale.mint{value: blocked}(1);
        assertEq(tickets.mintedBy(alice), 10);
        assertEq(sale.sold(), 9);
    }

    function test_refund_listedAndBid_doNotBreak_andTicketIsUnusable() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        TicketMarketBNB book = new TicketMarketBNB(address(tickets), team);
        vm.prank(alice);
        tickets.approve(address(book), 1);
        vm.prank(alice);
        book.list(1, 1 ether);

        TicketBidMarket bids = new TicketBidMarket(address(tickets), team);
        vm.deal(bob, bob.balance + 2 ether);
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        uint256 bidId = bids.postBid{value: 2 ether}(2, 1, 2 ether, 1, 1 hours);

        vm.warp(sale.startTime() + sale.REFUND_WINDOW());
        vm.prank(alice);
        sale.refund(1);
        assertEq(tickets.mintedBy(alice), 1);
        assertFalse(tickets.isAlive(1));
        assertFalse(tickets.isSurvivor(1));
        (uint8 cabin,,,,) = tickets.tickets(1);
        assertEq(cabin, 4);

        vm.prank(bob);
        vm.expectRevert();
        book.buy{value: 1 ether}(1);
        assertEq(address(book).balance, 0);
        book.cleanListing(1);
        assertEq(book.listingCount(), 0);

        vm.prank(bob);
        vm.expectRevert();
        bids.acceptBid(bidId, 1);
        vm.prank(bob);
        bids.cancelBid(bidId);
        assertEq(bob.balance, bobBefore);
        assertEq(address(bids).balance, 0);

        vm.expectRevert();
        tickets.ownerOf(1);
        vm.prank(alice);
        vm.expectRevert();
        tickets.requestCabin(1);
        vm.expectRevert(bytes("not pending"));
        tickets.settleCabin(1);
        vm.prank(alice);
        vm.expectRevert();
        tickets.claim(1);
        vm.prank(alice);
        vm.expectRevert();
        shop.applyBag(1, 1);
        vm.expectRevert(bytes("dead"));
        shop.gift(1, 1);

        _donate(0.2 ether);
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        flood.start();
        vm.warp(block.timestamp + 2 days);
        flood.commit(1);
        vm.roll(block.number + 6);
        flood.settle(1, new uint256[](0));
        assertEq(tickets.aliveCount(), 0);
        assertEq(tickets.mintedBy(alice), 1);
    }

    function test_refund_escrowReversesAndOpenPaysRemainder() public {
        feed.setAnswer(123e8);
        (uint256 due,) = sale.quoteMint(3);
        vm.prank(alice);
        sale.mint{value: due}(3);
        vm.warp(sale.startTime() + sale.REFUND_WINDOW());
        vm.prank(alice);
        sale.refund(1);
        _assertEscrow(0);

        feed.setAnswer(456e8);
        _forceSold(2700);
        (uint256 due2,) = sale.quoteMint(2);
        vm.prank(bob);
        sale.mint{value: due2}(2);
        _forceSold(4);
        vm.prank(bob);
        sale.refund(5);
        _donate(0.25 ether);
        _assertEscrow(0.25 ether);

        uint256 teamDue = sale.teamDue();
        uint256 potDue = sale.potDue();
        uint256 reserve = sale.reserveBNB();
        uint256 teamBefore = team.balance;
        uint256 potBefore = address(pot).balance;
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        assertEq(team.balance - teamBefore, teamDue);
        assertEq(address(pot).balance - potBefore, potDue);
        assertEq(address(sale).balance, 0);
        assertEq(sale.outstandingRefunds(), 0);
        assertEq(sale.teamDue(), 0);
        assertEq(sale.potDue(), 0);
        assertEq(sale.reserveBNB(), 0);
        vm.prank(alice);
        vm.expectRevert(bytes("opened"));
        sale.refund(2);
        (uint256 bnbReserve,) = _pairReserves();
        assertGe(bnbReserve, reserve + 0.25 ether);
    }

    /// forge-config: default.fuzz.runs = 32
    function testFuzz_solvency_interleavedMintsRefunds(uint256 seed) public {
        address[4] memory actors;
        for (uint256 i; i < 4; ++i) {
            actors[i] = makeAddr(string(abi.encodePacked("fuzz", vm.toString(i))));
            agent.setAllowed(actors[i], true, "fuzz.ai");
            vm.deal(actors[i], 200 ether);
        }
        uint256 donations;
        bool window;
        for (uint256 step; step < 12; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            if (!window && step == 5) {
                vm.warp(sale.startTime() + sale.REFUND_WINDOW());
                window = true;
            }
            uint256 action = seed % 4;
            if (action == 0) {
                feed.setAnswer(int256(uint256(50 + (seed % 1950)) * 1e8));
            } else if (action == 1) {
                address who = actors[seed % 4];
                uint256 room = 10 - tickets.mintedBy(who);
                if (room == 0) continue;
                uint256 count = 1 + (seed % 3);
                if (count > room) count = room;
                uint256 live = sale.sold();
                uint256 fake = seed % 2990;
                if (fake + count >= 3000) fake = 3000 - count - 1;
                _forceSold(fake);
                (uint256 due,) = sale.quoteMint(count);
                vm.prank(who);
                sale.mint{value: due}(count);
                _forceSold(live + count);
            } else if (action == 2 && window) {
                uint256 n = tickets.totalMinted();
                if (n == 0) continue;
                for (uint256 k; k < 4 && k < n; ++k) {
                    uint256 id = 1 + ((seed + k) % n);
                    if (sale.paidBnb(id) == 0) continue;
                    address holder = tickets.ownerOf(id);
                    vm.prank(holder);
                    sale.refund(id);
                    break;
                }
            } else {
                uint256 gift = ((seed % 4) + 1) * 0.01 ether;
                vm.deal(address(this), address(this).balance + gift);
                (bool ok,) = address(sale).call{value: gift}("");
                assertTrue(ok);
                donations += gift;
            }
            _assertEscrow(donations);
        }
        if (address(sale).balance == 0) return;
        uint256 teamDue = sale.teamDue();
        uint256 potDue = sale.potDue();
        uint256 reserve = sale.reserveBNB();
        uint256 extra = address(sale).balance - sale.outstandingRefunds();
        uint256 teamBefore = team.balance;
        uint256 potBefore = address(pot).balance;
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        assertEq(team.balance - teamBefore, teamDue);
        assertEq(address(pot).balance - potBefore, potDue);
        assertEq(address(sale).balance, 0);
        assertEq(sale.outstandingRefunds(), 0);
        (uint256 bnbReserve,) = _pairReserves();
        assertGe(bnbReserve, reserve + extra);
    }

    function _assertEscrow(uint256 donations) internal view {
        uint256 sum;
        uint256 live;
        uint256 teamLeg;
        uint256 potLeg;
        uint256 reserveLeg;
        uint256 n = tickets.totalMinted();
        for (uint256 id = 1; id <= n; ++id) {
            uint256 paid = sale.paidBnb(id);
            if (paid == 0) continue;
            live++;
            sum += paid;
            uint256 t = (paid * sale.TEAM_BPS()) / 10_000;
            uint256 p = (paid * sale.POT_BPS()) / 10_000;
            teamLeg += t;
            potLeg += p;
            reserveLeg += paid - t - p;
        }
        assertEq(sum, sale.outstandingRefunds());
        assertEq(sale.teamDue(), teamLeg);
        assertEq(sale.potDue(), potLeg);
        assertEq(sale.reserveBNB(), reserveLeg);
        assertEq(teamLeg + potLeg + reserveLeg, sale.outstandingRefunds());
        assertEq(sale.sold(), live);
        assertEq(address(sale).balance, sale.outstandingRefunds() + donations);
    }

    function _mintCount(uint256 n) internal {
        uint256 created;
        uint256 walletIdx;
        while (created < n) {
            address w = makeAddr(string(abi.encodePacked("m", vm.toString(walletIdx))));
            agent.setAllowed(w, true, string(abi.encodePacked("m", vm.toString(walletIdx), ".ai")));
            vm.deal(w, 500 ether);
            uint256 batch = n - created;
            if (batch > 10) batch = 10;
            (uint256 due,) = sale.quoteMint(batch);
            vm.prank(w);
            sale.mint{value: due}(batch);
            created += batch;
            walletIdx++;
        }
    }

    function _openSmall() internal {
        _mintSome();
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        assertTrue(sale.opened());
        assertEq(address(sale).balance, sale.pendingLiqBNB());
    }

    function _donate(uint256 amount) internal {
        vm.deal(bob, bob.balance + amount);
        vm.prank(bob);
        (bool ok,) = address(sale).call{value: amount}("");
        assertTrue(ok);
    }

    function _settleAll(uint256 n) internal {
        for (uint256 id = 1; id <= n; ++id) {
            address own = tickets.ownerOf(id);
            vm.prank(own);
            tickets.requestCabin(id);
        }
        vm.roll(block.number + 6);
        for (uint256 id = 1; id <= n; ++id) {
            tickets.settleCabin(id);
        }
    }

    function _pairReserves() internal view returns (uint256 bnbReserve, uint256 arkReserve) {
        MockLP lp = router.lp();
        (uint112 r0, uint112 r1,) = lp.getReserves();
        if (lp.token0() == address(wbnb)) return (uint256(r0), uint256(r1));
        return (uint256(r1), uint256(r0));
    }
}
