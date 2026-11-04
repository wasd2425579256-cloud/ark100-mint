// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TicketMarketBase} from "./TicketMarketBase.sol";

interface IArkLike {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title TicketMarketARK — ARK listings. BNB is rejected so this book never mixes currencies.
/// @notice Buyer approves ARK, then `buy`. Wallet-to-wallet ARK transfers are untaxed; a fee-on-transfer
///         token would fail the balance check. 2.5% of the ARK price goes to `feeRecipient`. No Agent ID.
contract TicketMarketARK is TicketMarketBase {
    IArkLike public immutable arkToken;

    constructor(address ticketNft_, address arkToken_, address feeRecipient_) TicketMarketBase(ticketNft_, feeRecipient_) {
        require(arkToken_ != address(0), "zero");
        arkToken = IArkLike(arkToken_);
    }

    function _collect(uint256 price) internal override {
        require(msg.value == 0, "no bnb");
        uint256 beforeBal = arkToken.balanceOf(address(this));
        _call(abi.encodeWithSelector(IArkLike.transferFrom.selector, msg.sender, address(this), price));
        require(arkToken.balanceOf(address(this)) - beforeBal == price, "tax");
    }

    function _pay(address seller, uint256 proceeds, uint256 fee) internal override {
        if (fee > 0) _call(abi.encodeWithSelector(IArkLike.transfer.selector, feeRecipient, fee));
        if (proceeds > 0) _call(abi.encodeWithSelector(IArkLike.transfer.selector, seller, proceeds));
    }

    function _call(bytes memory data) internal {
        (bool ok, bytes memory ret) = address(arkToken).call(data);
        require(ok, "ark");
        if (ret.length > 0) require(abi.decode(ret, (bool)), "ark");
    }
}
