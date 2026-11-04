// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Views and transfer surface the markets need from the live TicketNFT.
/// @dev `tickets` matches the deployed struct getter: cabin, lastClaim, mintedAt, minter, cabinCommitBlock.
interface ITicketNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function isAlive(uint256 tokenId) external view returns (bool);
    function cabinOf(uint256 tokenId) external view returns (uint8);
    function tickets(uint256 tokenId)
        external
        view
        returns (uint8 cabin, uint64 lastClaim, uint64 mintedAt, address minter, uint64 cabinCommitBlock);
}
