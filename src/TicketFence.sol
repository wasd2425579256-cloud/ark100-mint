// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITicketNFT} from "./interfaces/ITicketNFT.sol";

/// @notice Who may trade: afloat tickets with no cabin request in flight.
/// @dev Sunk (cabin 4 / not alive) and `cabinCommitBlock != 0` (mid requestCabin, including an
///      expired commit that has not been cleared) are rejected. Cabin 0 with no commit is listable:
///      the draw has not been asked for yet. Cabin, yield clock, and minter stay on TicketNFT.
abstract contract TicketFence {
    uint8 internal constant CABIN_SUNK = 4;

    ITicketNFT public immutable ticketNft;

    constructor(address ticketNft_) {
        require(ticketNft_ != address(0), "zero");
        ticketNft = ITicketNFT(ticketNft_);
    }

    function _approved(address owner, uint256 tokenId) internal view returns (bool) {
        return ticketNft.getApproved(tokenId) == address(this) || ticketNft.isApprovedForAll(owner, address(this));
    }

    function _listable(uint256 tokenId) internal view returns (bool) {
        (uint8 cabin,, uint64 mintedAt,, uint64 cabinCommitBlock) = ticketNft.tickets(tokenId);
        if (!ticketNft.isAlive(tokenId) || mintedAt == 0 || cabin == CABIN_SUNK) return false;
        if (cabinCommitBlock != 0) return false;
        return true;
    }
}
