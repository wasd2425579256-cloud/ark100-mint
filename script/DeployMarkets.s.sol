// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {TicketMarketBNB} from "../src/TicketMarketBNB.sol";
import {TicketMarketARK} from "../src/TicketMarketARK.sol";
import {TicketBidMarket} from "../src/TicketBidMarket.sol";

/// @notice Records the constructor args for the markets already deployed on BSC.
/// @dev Do not broadcast this again. A second run would deploy duplicate books.
///      Live addresses are already in js/chain.js:
///        TicketMarketBNB  0xC24b79485705cEF5AfF36fb4c4cCda34F8423d95
///          tx 0xc1d70e60ef4b9e7c3e1fb137b665701bcee5c9c0722eb16ec7b20bc68642055b
///        TicketMarketARK  0x3fF61e70B89dc5b0EDD9a7f27435d6604683Bd64
///          tx 0x1a8c2859d6957be284da4bf2353446467fb4cc0733d5392d943b7deede78abb0
///        TicketBidMarket  0xbC58134B8596e8A12050fcDF2435F42Ea0E2Aa32
///          tx 0x1277e5eca9d58adb69bab65b88848961afdf9ec408159f56a646f4f3444f67e7
///
///      Constructor args (BSC mainnet):
///        ticketNft     0x815202403e51C6525452dB09FC7c40dD2762D87e
///        arkToken      0xBCbA6cFc97d2c0A4Dcf22295D92EF5227B5db712
///        feeRecipient  ArkSale.projectWallet() == ArkToken.projectWallet()
///                      0xc4411B914853Db300A40a2d8F3BC5ec7538aCA74
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
