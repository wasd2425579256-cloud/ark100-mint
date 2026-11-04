// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TicketMarketBase} from "./TicketMarketBase.sol";

/// @title TicketMarketBNB — BNB listings for ARK100 tickets.
/// @notice NestEgg EggMarketV3 shape: seller approves, NFT stays in the seller wallet until buy,
///         2.5% of the price is paid to `feeRecipient`. Overpay is refunded. No Agent ID.
contract TicketMarketBNB is TicketMarketBase {
    constructor(address ticketNft_, address feeRecipient_) TicketMarketBase(ticketNft_, feeRecipient_) {}

    function _collect(uint256 price) internal override {
        require(msg.value >= price, "underpay");
    }

    function _pay(address seller, uint256 proceeds, uint256 fee) internal override {
        _send(seller, proceeds);
        _send(feeRecipient, fee);
        _send(msg.sender, msg.value - proceeds - fee);
    }

    function _send(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "pay");
    }
}
