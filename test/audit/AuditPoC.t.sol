// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Ark100Test} from "../Ark100.t.sol";

/// @notice Audit findings, inverted: each case asserts the old exploit can no longer land.
contract AuditPoC is Ark100Test {
    function test_expiredCabin_assignsEconomy_noRetry() public {
        (uint256 due,) = sale.quoteMint(10);
        vm.prank(alice);
        sale.mint{value: due}(10);

        for (uint256 id = 1; id <= 10; ++id) {
            vm.prank(alice);
            tickets.requestCabin(id);
        }
        // Past the 256-block window. The old path cleared the commit and rolled again until captain.
        vm.roll(block.number + 6 + 257);
        for (uint256 id = 1; id <= 10; ++id) {
            (bool ok,) = address(tickets).call(abi.encodeWithSignature("retryCabin(uint256)", id));
            assertFalse(ok, "retry removed");
            vm.prank(bob);
            tickets.settleCabin(id);
            assertEq(tickets.cabinOf(id), tickets.CABIN_ECONOMY(), "expired is economy");
        }
        assertEq(tickets.survivorCount(), 10);
    }

    function test_sandbagAfterCommit_cannotDodge() public {
        _mintCount(30);
        _settleAll(30);
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        flood.start();
        vm.warp(block.timestamp + 2 days);
        flood.commit(1);
        vm.roll(block.number + 6);

        uint256 snap = vm.snapshotState();
        _settleDay(1);
        uint256 victim;
        for (uint256 id = 1; id <= 30; ++id) {
            if (!tickets.isAlive(id)) {
                victim = id;
                break;
            }
        }
        vm.revertToState(snap);
        require(victim != 0, "no sink");

        address o = tickets.ownerOf(victim);
        vm.prank(address(tickets));
        ark.mint(o, 10_000_000 ether);
        vm.startPrank(o);
        ark.approve(address(shop), type(uint256).max);
        shop.buy(1);
        vm.expectRevert(bytes("committed"));
        shop.applyBag(victim, 1);
        vm.stopPrank();

        _settleDay(1);
        assertFalse(tickets.isAlive(victim), "doomed ticket still sinks");
    }

    function test_sandbagBeforeCommit_protectsOneTicket() public {
        _mintCount(30);
        _settleAll(30);
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        flood.start();

        address o = tickets.ownerOf(1);
        vm.prank(address(tickets));
        ark.mint(o, 10_000_000 ether);
        vm.startPrank(o);
        ark.approve(address(shop), type(uint256).max);
        shop.buy(1);
        shop.applyBag(1, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        flood.commit(1);
        vm.roll(block.number + 6);
        _settleDay(1);

        assertTrue(tickets.isAlive(1), "bag before commit holds");
        assertFalse(shop.protectedUntil(1, 1), "bag consumed");
        (,, uint8 water, uint32 sunk) = flood.dayState(1);
        // 29 exposed, not 30. The protected id is outside the sink draw.
        assertEq(sunk, uint32((29 * uint256(water) + 99) / 100));
    }

    function test_giftBeforeOpen_doesNotBlockRefund() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        vm.prank(address(tickets));
        ark.mint(bob, 10_000_000 ether);
        vm.startPrank(bob);
        ark.approve(address(shop), type(uint256).max);
        shop.buy(1);
        vm.expectRevert(bytes("not open"));
        shop.gift(1, 1);
        vm.stopPrank();
        assertFalse(tickets.yieldClaimed(1));

        vm.warp(block.timestamp + 7 days + 1);
        uint256 bal = alice.balance;
        vm.prank(alice);
        sale.refund(1);
        assertEq(alice.balance, bal + due);
        assertEq(sale.sold(), 0);
    }

    function test_claimBeforeOpen_reverts() public {
        (uint256 due,) = sale.quoteMint(1);
        vm.prank(alice);
        sale.mint{value: due}(1);
        vm.prank(alice);
        tickets.requestCabin(1);
        vm.roll(block.number + 6);
        tickets.settleCabin(1);
        vm.warp(block.timestamp + 2 days);
        assertGt(tickets.pendingArk(1), 0);
        vm.prank(alice);
        vm.expectRevert(bytes("not open"));
        tickets.claim(1);
        assertFalse(tickets.yieldClaimed(1));
        assertEq(ark.balanceOf(alice), 0);
    }

    function test_requestClosesAtNight100_andStaysOpenBefore() public {
        (uint256 due,) = sale.quoteMint(2);
        vm.prank(alice);
        sale.mint{value: due}(2);
        _forceSold(sale.OPEN_AT());
        sale.openPool();
        flood.start();

        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        tickets.requestCabin(1);

        vm.warp(block.timestamp + 120 days);
        assertTrue(flood.requestsClosed());
        vm.prank(alice);
        vm.expectRevert(bytes("flood closed"));
        tickets.requestCabin(2);
        assertEq(tickets.cabinOf(2), 0);
        assertFalse(tickets.isSurvivor(2));
        // The in-flight request can still be settled after the cutoff.
        vm.roll(block.number + 6);
        tickets.settleCabin(1);
        assertTrue(tickets.isSurvivor(1));
    }

    function test_pendingTicketsCannotDodgeFloodOrPot() public {
        _mintCount(120);
        // Honest cabins: 21..120. Dodgers 1..20 never request.
        for (uint256 id = 21; id <= 120; ++id) {
            vm.prank(tickets.ownerOf(id));
            tickets.requestCabin(id);
        }
        vm.roll(block.number + 6);
        for (uint256 id = 21; id <= 120; ++id) tickets.settleCabin(id);
        assertEq(tickets.survivorCount(), 100);

        _forceSold(sale.OPEN_AT());
        sale.openPool();
        flood.start();

        vm.warp(block.timestamp + 2 days);
        flood.commit(1);
        vm.roll(block.number + 6);
        _settleDay(1);
        (,, uint8 water1, uint32 sunk1) = flood.dayState(1);
        uint256 allExposed = (120 * uint256(water1) + 99) / 100;
        uint256 cabinsOnly = (100 * uint256(water1) + 99) / 100;
        assertEq(sunk1, allExposed, "pending ids are in the night");
        assertGt(allExposed, cabinsOnly, "skipping pending would sink fewer");

        for (uint256 d = 2; d <= 100; ++d) {
            vm.warp(block.timestamp + 1 days);
            flood.commit(d);
            vm.roll(block.number + 6);
            _settleDay(d);
        }

        uint256 honest;
        uint256 dodgerSurvivors;
        uint256 dodgerAlive;
        for (uint256 id = 1; id <= 120; ++id) {
            if (!tickets.isSurvivor(id)) {
                if (id <= 20 && tickets.isAlive(id)) dodgerAlive++;
                continue;
            }
            if (id <= 20) dodgerSurvivors++;
            else honest++;
        }
        assertEq(dodgerSurvivors, 0, "pending never becomes a survivor");
        emit log_named_uint("honest survivors", honest);
        emit log_named_uint("dodgers still pending", dodgerAlive);

        for (uint256 id = 1; id <= 20; ++id) {
            if (!tickets.isAlive(id)) continue;
            vm.prank(tickets.ownerOf(id));
            vm.expectRevert(bytes("flood closed"));
            tickets.requestCabin(id);
            assertFalse(tickets.isSurvivor(id));
        }

        if (honest > 0) {
            flood.landfall();
            assertEq(pot.survivorCount(), honest);
        }
    }
}

/// @notice 3_000 and 10_000 ticket settlement must stay under 10M gas per transaction.
contract AuditGas is Ark100Test {
    function test_gas_settleAndLand_3000() public {
        uint256 maxGas = _gasNight(3_000, 200);
        assertLt(maxGas, 10_000_000, "3k batch");
    }

    function test_gas_settleAndLand_10000() public {
        uint256 maxGas = _gasNight(10_000, 400);
        assertLt(maxGas, 10_000_000, "10k batch");
    }

    function _gasNight(uint256 n, uint256 cabins) internal returns (uint256 maxGas) {
        uint256 mintedBefore = tickets.totalMinted();
        for (uint256 i = 1; i <= n; ++i) {
            address w = address(uint160(0xA000 + mintedBefore + i));
            vm.prank(address(sale));
            tickets.mintTo(w, w);
        }
        uint256 from = mintedBefore + 1;
        uint256 cabinEnd = from + cabins - 1;
        for (uint256 id = from; id <= cabinEnd; ++id) {
            vm.prank(tickets.ownerOf(id));
            tickets.requestCabin(id);
        }
        vm.roll(block.number + 6);
        for (uint256 id = from; id <= cabinEnd; ++id) tickets.settleCabin(id);

        if (!sale.opened()) {
            if (address(sale).balance == 0) {
                vm.deal(address(sale), 1 ether);
            }
            _forceSold(sale.OPEN_AT());
            sale.openPool();
        }
        if (!flood.started()) flood.start();

        // Jump to night 100. Cabins were drawn before this boundary, so requests are already closed
        // only after the warp below.
        vm.warp(block.timestamp + 120 days);
        uint256 day = 100;
        flood.commit(day);
        vm.roll(block.number + 6);

        uint256 guard;
        while (true) {
            (, bool settled,,) = flood.dayState(day);
            if (settled) break;
            uint256 g0 = gasleft();
            flood.settleBatch(day, 10_000);
            uint256 used = g0 - gasleft();
            if (used > maxGas) maxGas = used;
            assertLt(used, 10_000_000, "batch");
            guard++;
            require(guard < 10_000, "loop");
        }
        assertGt(tickets.survivorCount(), 0, "land needs a survivor");
        uint256 gLand = gasleft();
        flood.landfall();
        uint256 landGas = gLand - gasleft();
        console2.log("land gas", n, landGas);
        console2.log("max batch gas", n, maxGas);
        assertLt(landGas, 10_000_000, "land");
        assertTrue(pot.landed());
        assertEq(pot.survivorCount(), tickets.survivorCount());
    }
}
