// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArkSale} from "../src/ArkSale.sol";
import {ArkToken} from "../src/ArkToken.sol";
import {ArkPot} from "../src/ArkPot.sol";
import {TicketNFT} from "../src/TicketNFT.sol";
import {FloodEngine} from "../src/FloodEngine.sol";
import {SandbagShop} from "../src/SandbagShop.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockAggregator} from "../src/mocks/MockAggregator.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";

/// @dev Post-open sequences: mints, direct BNB, and permissionless zaps.
contract SaleHandler is Test {
    ArkSale public sale;
    uint256 internal constant SOLD_SLOT = 3;

    function init(ArkSale sale_, MockAgentId agent) external {
        sale = sale_;
        agent.setAllowed(address(this), true, "handler.ai");
        vm.deal(address(this), 1000 ether);
        // Open with the real escrow from a few tickets, then pretend the counter reached 3000.
        (uint256 due,) = sale.quoteMint(10);
        sale.mint{value: due}(10);
        vm.store(address(sale), bytes32(SOLD_SLOT), bytes32(sale.OPEN_AT()));
        sale.openPool();
    }

    function mintOne() external {
        (uint256 due,) = sale.quoteMint(1);
        if (address(this).balance < due) return;
        try sale.mint{value: due}(1) {} catch {}
    }

    function donate() external {
        if (address(this).balance < 0.2 ether) return;
        (bool ok,) = address(sale).call{value: 0.2 ether}("");
        if (ok && sale.opened()) {
            try sale.syncPending() {} catch {}
        }
    }

    function addLiq() external {
        try sale.addLiquidity() {} catch {}
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// forge-config: default.invariant.runs = 30
/// forge-config: default.invariant.depth = 8
/// forge-config: default.invariant.fail_on_revert = false
contract ArkSaleInvariantTest is Test {
    ArkSale sale;
    ArkToken ark;
    SaleHandler handler;

    function setUp() public {
        address team = makeAddr("team");
        MockAgentId agent = new MockAgentId();
        MockAggregator feed = new MockAggregator(700e8);
        MockWETH wbnb = new MockWETH();
        MockRouter router = new MockRouter(wbnb);
        ArkPot pot = new ArkPot();
        FloodEngine flood = new FloodEngine();
        TicketNFT tickets = new TicketNFT();
        ark = new ArkToken(team, address(pot));
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

        handler = new SaleHandler();
        handler.init(sale, agent);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SaleHandler.mintOne.selector;
        selectors[1] = SaleHandler.donate.selector;
        selectors[2] = SaleHandler.addLiq.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev After open, ticket splits are paid out immediately. BNB left on the sale is the zap balance
    ///      (including dust and adopted donations). Zaps do not mint ARK.
    function invariant_postOpenAccounting() public view {
        assertTrue(sale.opened());
        assertEq(sale.teamDue(), 0);
        assertEq(sale.potDue(), 0);
        assertEq(sale.reserveBNB(), 0);
        assertEq(sale.outstandingRefunds(), 0);
        assertEq(sale.pendingLiqBNB(), address(sale).balance);
        assertEq(ark.totalSupply(), sale.POOL_SEED_ARK());
        assertLt(address(sale).balance, 50 ether);
    }
}
