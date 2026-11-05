// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPancakeFactory, IPancakePair} from "../../src/interfaces/IPancake.sol";
import {Ark100Test} from "../Ark100.t.sol";

/// @notice Mock-pair cover for the pre-open WBNB donation that used to revert `openPool` ("pair seeded").
contract PairGrief is Ark100Test {
    function test_syncedWbnbDonation_openStillSucceeds() public {
        _mintSome();
        address factory_ = address(router.factory_());
        address pair = IPancakeFactory(factory_).createPair(address(ark), address(wbnb));

        vm.deal(address(this), 1 ether);
        wbnb.deposit{value: 1 ether}();
        wbnb.transfer(pair, 1000);
        IPancakePair(pair).sync();
        (uint112 r0, uint112 r1,) = IPancakePair(pair).getReserves();
        assertTrue(r0 != 0 || r1 != 0, "donation synced");

        uint256 reserve = sale.reserveBNB();
        _forceSold(sale.OPEN_AT());
        sale.openPool();

        assertTrue(sale.opened());
        assertEq(sale.pair(), pair);
        assertEq(ark.officialPair(), pair);
        assertGt(ark.poolOpenBlock(), 0);
        assertGt(IPancakePair(pair).balanceOf(sale.DEAD()), 0);
        (uint256 bnbReserve, uint256 arkReserve) = _pairReserves();
        // The 1000 wei stays in the pair (it was already a reserve). The genesis add is on top.
        assertGe(bnbReserve, reserve + 1000);
        assertGt(arkReserve, 0);
        assertEq(address(sale).balance, 0);
    }

    function test_unsyncedDonation_isSkimmed_openUsesFullSeed() public {
        _mintSome();
        address factory_ = address(router.factory_());
        address pair = IPancakeFactory(factory_).createPair(address(ark), address(wbnb));

        vm.deal(address(this), 2 ether);
        wbnb.deposit{value: 1 ether}();
        wbnb.transfer(pair, 1 ether);
        // Not synced: balance is ahead of reserves. Open must skim it, not price against it.
        (uint112 r0, uint112 r1,) = IPancakePair(pair).getReserves();
        assertEq(r0, 0);
        assertEq(r1, 0);

        uint256 reserve = sale.reserveBNB();
        _forceSold(sale.OPEN_AT());
        sale.openPool();

        assertTrue(sale.opened());
        (uint256 bnbReserve,) = _pairReserves();
        assertApproxEqAbs(bnbReserve, reserve, 1000);
        assertLt(bnbReserve, reserve + 0.1 ether);
        assertGe(wbnb.balanceOf(sale.DEAD()), 1 ether);
    }

    function test_existingLp_openDoesNotRevert() public {
        _mintSome();
        address factory_ = address(router.factory_());
        address pair = IPancakeFactory(factory_).createPair(address(ark), address(wbnb));

        // The mock pair is not the predicted launch pair, so this transfer is allowed here.
        // On BSC the same transfer to `launchPair` reverts ("pair locked") — see the fork test.
        vm.prank(address(tickets));
        ark.mint(address(this), 1 ether);
        ark.transfer(pair, 1 ether);
        vm.deal(address(this), 1 ether);
        wbnb.deposit{value: 0.01 ether}();
        wbnb.transfer(pair, 0.01 ether);
        IPancakePair(pair).mint(address(this));
        assertGt(IPancakePair(pair).totalSupply(), 0);

        _forceSold(sale.OPEN_AT());
        sale.openPool();
        assertTrue(sale.opened());
        assertGt(IPancakePair(pair).balanceOf(sale.DEAD()), 0);
        assertEq(ark.officialPair(), pair);
    }
}
