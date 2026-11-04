// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {TicketMarketBNB} from "../src/TicketMarketBNB.sol";
import {TicketMarketARK} from "../src/TicketMarketARK.sol";
import {TicketBidMarket} from "../src/TicketBidMarket.sol";

/// @notice Deploy TicketMarketBNB, TicketMarketARK, and TicketBidMarket.
/// @dev Do not broadcast from CI. This PR does not deploy. After a real deploy, paste the three
///      addresses into js/chain.js (marketBnb, marketArk, marketBid), replacing the zero addresses.
///
///      Constructor args (BSC mainnet):
///        ticketNft     0x815202403e51C6525452dB09FC7c40dD2762D87e
///        arkToken      0xBCbA6cFc97d2c0A4Dcf22295D92EF5227B5db712
///        feeRecipient  ArkSale.projectWallet() == ArkToken.projectWallet()
///                      0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74
///
///      forge script script/DeployMarkets.s.sol --rpc-url $BSC_RPC --broadcast --private-key $DEPLOYER_KEY
contract DeployMarkets is Script {
    address internal constant TICKET_NFT = 0x815202403e51C6525452dB09FC7c40dD2762D87e;
    address internal constant ARK = 0xBCbA6cFc97d2c0A4Dcf22295D92EF5227B5db712;
    /// @dev Read from ArkSale.projectWallet() on BSC mainnet. Not a freshly chosen address.
    address internal constant FEE_RECIPIENT = 0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74;

    function run() external {
        vm.startBroadcast();
        TicketMarketBNB bnb = new TicketMarketBNB(TICKET_NFT, FEE_RECIPIENT);
        TicketMarketARK ark = new TicketMarketARK(TICKET_NFT, ARK, FEE_RECIPIENT);
        TicketBidMarket bid = new TicketBidMarket(TICKET_NFT, FEE_RECIPIENT);
        vm.stopBroadcast();
        console2.log("TicketMarketBNB", address(bnb));
        console2.log("TicketMarketARK", address(ark));
        console2.log("TicketBidMarket", address(bid));
    }
}
