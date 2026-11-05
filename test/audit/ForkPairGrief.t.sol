// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArkPot} from "../../src/ArkPot.sol";
import {ArkToken} from "../../src/ArkToken.sol";
import {TicketNFT} from "../../src/TicketNFT.sol";
import {FloodEngine} from "../../src/FloodEngine.sol";
import {SandbagShop} from "../../src/SandbagShop.sol";
import {ArkSale} from "../../src/ArkSale.sol";

interface IFac {
    function createPair(address, address) external returns (address);
    function getPair(address, address) external view returns (address);
}

interface IPair {
    function sync() external;
    function getReserves() external view returns (uint112, uint112, uint32);
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IW {
    function deposit() external payable;
    function transfer(address, uint256) external returns (bool);
}

/// @notice BSC fork: a pre-created ARK/WBNB pair with 1 wei of synced WBNB must not brick `openPool`.
///         ARK still cannot be pushed into that pair by anyone but the sale before open.
contract ForkPairGrief is Test {
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
    address constant AGENT = 0xf14F5cF3fCB976082Df08dA1609D1698C39Ff2e2;
    address constant TEAM = 0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74;
    uint256 constant SOLD_SLOT = 3;

    function setUp() public {
        vm.createSelectFork(vm.envOr("BSC_RPC", string("https://bsc-dataseed.binance.org")));
    }

    function test_wbnbDonation_doesNotBrickOpen_andArkStaysLocked() public {
        ArkSale sale = _deploy();
        ArkToken ark = ArkToken(address(sale.arkToken()));
        TicketNFT tickets = TicketNFT(address(sale.ticketNft()));

        address attacker = address(0xBEEF);
        vm.deal(attacker, 1 ether);
        vm.startPrank(attacker);
        address pair = IFac(FACTORY).createPair(address(ark), WBNB);
        assertEq(pair, ark.launchPair(), "predicted pair");
        IW(WBNB).deposit{value: 1000}();
        IW(WBNB).transfer(pair, 1000);
        IPair(pair).sync();
        vm.stopPrank();
        (uint112 r0, uint112 r1,) = IPair(pair).getReserves();
        assertTrue(r0 != 0 || r1 != 0, "synced");

        vm.prank(address(tickets));
        ark.mint(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert(bytes("pair locked"));
        ark.transfer(pair, 1 ether);

        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(uint256(3000)));
        vm.deal(address(sale), 10 ether);
        sale.openPool();

        assertTrue(sale.opened());
        assertEq(sale.pair(), pair);
        assertEq(ark.officialPair(), pair);
        assertGt(ark.poolOpenBlock(), 0);
        assertGt(IPair(pair).balanceOf(sale.DEAD()), 0);
        assertGt(IPair(pair).totalSupply(), 0);
        (uint112 a0, uint112 a1,) = IPair(pair).getReserves();
        assertGt(uint256(a0) + uint256(a1), 1000);
    }

    function _deploy() internal returns (ArkSale sale) {
        ArkPot pot = new ArkPot();
        ArkToken ark = new ArkToken(TEAM, address(pot));
        TicketNFT tickets = new TicketNFT();
        FloodEngine flood = new FloodEngine();
        SandbagShop shop = new SandbagShop(address(ark), address(tickets), address(flood));
        sale = new ArkSale(TEAM, address(pot), AGENT, FEED, ROUTER);

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
    }
}
