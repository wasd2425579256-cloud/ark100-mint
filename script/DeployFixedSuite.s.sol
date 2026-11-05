// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ArkPot} from "../src/ArkPot.sol";
import {ArkToken} from "../src/ArkToken.sol";
import {TicketNFT} from "../src/TicketNFT.sol";
import {FloodEngine} from "../src/FloodEngine.sol";
import {SandbagShop} from "../src/SandbagShop.sol";
import {ArkSale} from "../src/ArkSale.sol";
import {TicketMarketBNB} from "../src/TicketMarketBNB.sol";
import {TicketMarketARK} from "../src/TicketMarketARK.sol";
import {TicketBidMarket} from "../src/TicketBidMarket.sol";

/// @title DeployFixedSuite — full ARK100 redeploy. Does not broadcast unless the operator passes
///        `forge script --broadcast`. This repository run must not broadcast.
///
///        The suite at ArkSale `0xB69f1F7A14dbCbB82A5eFcCB4B7579410eEc746E` was never started
///        (`startTime` is 0). Per-ticket refunds change ArkSale and TicketNFT, and every wire is
///        one-shot, so redeploy this whole script. After a real broadcast, point `js/chain.js` at
///        the new addresses.
///
/// Contracts that must be redeployed together (each is wired once, or takes an address in its constructor):
///   1. ArkPot            — `sale` and `floodEngine` are one-shot; `setTicketNft` is only callable by the sale
///   2. ArkToken          — `sale`, `ticketNft`, and `sandbagShop` are one-shot; only that sale may set the pair
///   3. TicketNFT         — `sale`, `floodEngine`, and `arkToken` are one-shot
///   4. FloodEngine       — `wire(nft, shop, pot, sale)` is one-shot
///   5. SandbagShop       — ark, nft, and flood are immutable constructor args
///   6. ArkSale           — the post-open liquidity fix; `wire(nft, ark)` is one-shot and points the pot at the nft
///   7. TicketMarketBNB   — ticket nft is immutable. The live book cannot list the new nft.
///   8. TicketMarketARK   — ticket nft and ARK are immutable
///   9. TicketBidMarket   — ticket nft is immutable
///
/// Reused from BSC mainnet (not redeployed):
///   projectWallet  0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74   (existing ArkSale / ArkToken project wallet)
///   agentId        0xf14F5cF3fCB976082Df08dA1609D1698C39Ff2e2
///   bnbUsd feed    0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE   (Chainlink BNB/USD, 8 decimals)
///   router         0x10ED43C718714eb63d5aA57B78B54704E256024E   (PancakeSwap V2)
///
/// The live markets (0xC24b…, 0x3fF6…, 0xbC58…) stay pointed at the old TicketNFT. They are not upgraded.
/// Point js/chain.js at the new addresses after a real broadcast.
///
/// Selectors the site / ops scripts must use after this redeploy (constructors and wire order are unchanged):
///   FloodEngine.settleBatch(uint256 day, uint256 maxCount)  0xad28484a
///       Repeat until dayState(day).settled. maxCount is capped on-chain at MAX_BATCH (400).
///   FloodEngine.landfall()                                  0x111bfda0
///       No survivor id list. Call after night 100 is fully settled.
///   ArkPot.land()                                           0x8c980129
///       Flood only. Reads TicketNFT.survivorCount().
///   TicketBidMarket.activeBidIds(uint256 offset, uint256 limit)  0x6d8ffe99
///       Page size 1..100. activeBidIds() remains for small books.
///   TicketBidMarket.MIN_UNIT_PRICE()                        0xb4532247  (0.001 BNB)
///
/// Order matters: every `deployer` check is `msg.sender`, so this script must be the sender for every deploy
/// and every one-shot setter. `pot.setTicketNft` is called by `sale.wire`, not by the deployer directly.
/// `startSale` is skipped unless START_TIME is set (unix seconds, or 0 to use block.timestamp when you set it).
contract DeployFixedSuite is Script {
    address internal constant PROJECT_WALLET = 0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74;
    address internal constant AGENT_ID = 0xf14F5cF3fCB976082Df08dA1609D1698C39Ff2e2;
    address internal constant BNB_USD_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
    address internal constant PANCAKE_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    function run() external {
        uint256 startTime = vm.envOr("START_TIME", uint256(0));

        vm.startBroadcast();

        // 1. Pot and token first. The token's tax sink is the pot. Neither knows the sale yet.
        ArkPot pot = new ArkPot();
        ArkToken ark = new ArkToken(PROJECT_WALLET, address(pot));

        // 2. Ticket, flood, shop. Shop binds ark + nft + flood immutably, so those three exist first.
        TicketNFT tickets = new TicketNFT();
        FloodEngine flood = new FloodEngine();
        SandbagShop shop = new SandbagShop(address(ark), address(tickets), address(flood));

        // 3. Sale. Constructor does not wire the nft or the token.
        ArkSale sale = new ArkSale(PROJECT_WALLET, address(pot), AGENT_ID, BNB_USD_FEED, PANCAKE_V2_ROUTER);

        // 4. One-shot wiring. pot.setSale must precede sale.wire, because wire calls pot.setTicketNft.
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

        // 5. Markets against the new nft (and the new ARK, for the ARK book). Fee recipient stays the project wallet.
        TicketMarketBNB marketBnb = new TicketMarketBNB(address(tickets), PROJECT_WALLET);
        TicketMarketARK marketArk = new TicketMarketARK(address(tickets), address(ark), PROJECT_WALLET);
        TicketBidMarket marketBid = new TicketBidMarket(address(tickets), PROJECT_WALLET);

        // 6. Optional. Leave unset to keep the sale on "not started" until the deployer calls startSale.
        if (startTime != 0) {
            sale.startSale(startTime);
        }

        vm.stopBroadcast();

        require(sale.projectWallet() == PROJECT_WALLET, "wallet");
        require(ark.projectWallet() == PROJECT_WALLET, "wallet");
        require(ark.taxPot() == address(pot), "tax pot");
        require(ark.sale() == address(sale), "ark sale");
        require(ark.ticketNft() == address(tickets), "ark nft");
        require(ark.sandbagShop() == address(shop), "ark shop");
        require(tickets.sale() == address(sale), "nft sale");
        require(tickets.floodEngine() == address(flood), "nft flood");
        require(address(tickets.arkToken()) == address(ark), "nft ark");
        require(pot.sale() == address(sale), "pot sale");
        require(pot.floodEngine() == address(flood), "pot flood");
        require(address(pot.ticketNft()) == address(tickets), "pot nft");
        require(address(flood.ticketNft()) == address(tickets), "flood nft");
        require(address(flood.sandbagShop()) == address(shop), "flood shop");
        require(address(flood.pot()) == address(pot), "flood pot");
        require(flood.sale() == address(sale), "flood sale");
        require(address(sale.ticketNft()) == address(tickets), "sale nft");
        require(address(sale.arkToken()) == address(ark), "sale ark");
        require(shop.floodEngine() == address(flood), "shop flood");
        require(marketBnb.feeRecipient() == PROJECT_WALLET, "fee");
        require(address(marketArk.arkToken()) == address(ark), "mkt ark");
        require(marketBid.feeRecipient() == PROJECT_WALLET, "fee");

        console2.log("ArkPot", address(pot));
        console2.log("ArkToken", address(ark));
        console2.log("TicketNFT", address(tickets));
        console2.log("FloodEngine", address(flood));
        console2.log("SandbagShop", address(shop));
        console2.log("ArkSale", address(sale));
        console2.log("TicketMarketBNB", address(marketBnb));
        console2.log("TicketMarketARK", address(marketArk));
        console2.log("TicketBidMarket", address(marketBid));
        console2.log("launchPair", ark.launchPair());
        if (startTime == 0) {
            console2.log("startSale NOT called; deployer calls startSale(timestamp) before mint");
        }
    }
}
