// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MarketFee} from "./MarketFee.sol";
import {TicketFence} from "./TicketFence.sol";

/// @notice Shared listing book. Payment is implemented by the BNB and ARK markets so the two
///         currencies never share a contract.
abstract contract TicketMarketBase is ReentrancyGuard, TicketFence {
    uint256 public constant MARKET_FEE_BPS = MarketFee.BPS;

    address public immutable feeRecipient;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;
    uint256[] internal _active;
    mapping(uint256 => uint256) internal _pos;

    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event Bought(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price, uint256 fee);
    event Cancelled(uint256 indexed tokenId, address indexed seller);
    event ListingCleaned(uint256 indexed tokenId, address indexed caller);

    constructor(address ticketNft_, address feeRecipient_) TicketFence(ticketNft_) {
        require(feeRecipient_ != address(0), "zero");
        feeRecipient = feeRecipient_;
    }

    function feeOn(uint256 amount) public pure returns (uint256 fee, uint256 proceeds) {
        return MarketFee.split(amount);
    }

    function listable(uint256 tokenId) external view returns (bool) {
        return _listable(tokenId);
    }

    function quote(uint256 tokenId) external view returns (uint256 price, uint256 fee, uint256 sellerProceeds) {
        price = listings[tokenId].price;
        (fee, sellerProceeds) = MarketFee.split(price);
    }

    function listingCount() external view returns (uint256) {
        return _active.length;
    }

    function listingIdAt(uint256 index) external view returns (uint256) {
        return _active[index];
    }

    function activeListingIds() external view returns (uint256[] memory) {
        return _active;
    }

    /// @notice True when the stored seller still owns the ticket, the market is approved, and the
    ///         ticket is still listable. Buy reverts otherwise; anyone may `cleanListing`.
    function buyable(uint256 tokenId) external view returns (bool) {
        return _buyable(tokenId);
    }

    /// @notice Seller keeps the NFT (approve or setApprovalForAll). Price is wei of this market's currency.
    function list(uint256 tokenId, uint256 priceWei) external {
        require(priceWei > 0, "price");
        require(listings[tokenId].seller == address(0), "listed");
        require(ticketNft.ownerOf(tokenId) == msg.sender, "not owner");
        require(_approved(msg.sender, tokenId), "not approved");
        require(_listable(tokenId), "not listable");
        listings[tokenId] = Listing({seller: msg.sender, price: priceWei});
        _activate(tokenId);
        emit Listed(tokenId, msg.sender, priceWei);
    }

    function cancel(uint256 tokenId) external {
        Listing memory listing = listings[tokenId];
        require(listing.seller == msg.sender, "not seller");
        _clear(tokenId);
        emit Cancelled(tokenId, msg.sender);
    }

    /// @notice Drop a row the seller can no longer fill: moved, approval pulled, sunk, or mid-cabin.
    function cleanListing(uint256 tokenId) external {
        Listing memory listing = listings[tokenId];
        require(listing.seller != address(0), "unlisted");
        require(!_buyable(tokenId), "live");
        _clear(tokenId);
        emit ListingCleaned(tokenId, msg.sender);
    }

    function buy(uint256 tokenId) external payable nonReentrant {
        Listing memory listing = listings[tokenId];
        require(listing.seller != address(0), "unlisted");
        address owner = ticketNft.ownerOf(tokenId);
        require(owner == listing.seller, "stale");
        require(_approved(owner, tokenId), "not approved");
        require(_listable(tokenId), "not listable");
        uint256 price = listing.price;
        _clear(tokenId);
        _collect(price);
        (uint256 fee, uint256 proceeds) = MarketFee.split(price);
        ticketNft.transferFrom(owner, msg.sender, tokenId);
        _pay(owner, proceeds, fee);
        emit Bought(tokenId, msg.sender, owner, price, fee);
    }

    function _buyable(uint256 tokenId) internal view returns (bool) {
        Listing memory listing = listings[tokenId];
        if (listing.seller == address(0)) return false;
        try ticketNft.ownerOf(tokenId) returns (address owner) {
            return owner == listing.seller && _approved(owner, tokenId) && _listable(tokenId);
        } catch {
            return false;
        }
    }

    function _collect(uint256 price) internal virtual;

    function _pay(address seller, uint256 proceeds, uint256 fee) internal virtual;

    function _activate(uint256 id) internal {
        _active.push(id);
        _pos[id] = _active.length;
    }

    function _clear(uint256 id) internal {
        uint256 pos = _pos[id];
        require(pos != 0, "index");
        uint256 lastId = _active[_active.length - 1];
        _active[pos - 1] = lastId;
        _pos[lastId] = pos;
        _active.pop();
        delete _pos[id];
        delete listings[id];
    }
}
