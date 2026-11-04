// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MarketFee} from "./MarketFee.sol";
import {TicketFence} from "./TicketFence.sol";

/// @title TicketBidMarket — BNB quantity bids (NestEgg EggBidMarketV2).
/// @notice Kind 0 any listable ticket, kind 1 cabin (`param` 0 pending, 1 economy, 2 business, 3 captain),
///         kind 2 one specific tokenId (`qty` must be 1). Escrow is `unitPrice * qty` in BNB.
///         Each fill pays 2.5% to `feeRecipient` and the rest to the seller. No Agent ID.
contract TicketBidMarket is ReentrancyGuard, TicketFence {
    uint256 public constant MARKET_FEE_BPS = MarketFee.BPS;
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant MAX_DURATION = 30 days;
    uint8 public constant KIND_ANY = 0;
    uint8 public constant KIND_CABIN = 1;
    uint8 public constant KIND_TOKEN = 2;

    address public immutable feeRecipient;
    uint256 public nextBidId = 1;

    struct Bid {
        address buyer;
        uint256 unitPrice;
        uint256 qtyLeft;
        uint8 kind;
        uint256 param;
        uint64 expires;
        bool open;
    }

    mapping(uint256 => Bid) internal _bids;
    uint256[] internal _active;
    mapping(uint256 => uint256) internal _pos;

    event BidPosted(
        uint256 indexed bidId,
        address indexed buyer,
        uint8 kind,
        uint256 param,
        uint256 unitPrice,
        uint256 qty,
        uint64 expires
    );
    event BidFilled(
        uint256 indexed bidId,
        uint256 indexed tokenId,
        address indexed seller,
        address buyer,
        uint256 unitPrice,
        uint256 fee,
        uint256 qtyLeft
    );
    event BidCancelled(uint256 indexed bidId, address indexed buyer, uint256 refund);
    event BidExpired(uint256 indexed bidId, address indexed buyer, uint256 refund);

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

    function bidOf(uint256 bidId)
        external
        view
        returns (address buyer, uint256 unitPrice, uint256 qtyLeft, uint8 kind, uint256 param, uint64 expires, bool open)
    {
        Bid memory b = _bids[bidId];
        return (b.buyer, b.unitPrice, b.qtyLeft, b.kind, b.param, b.expires, b.open);
    }

    function bidCount() external view returns (uint256) {
        return _active.length;
    }

    function bidIdAt(uint256 index) external view returns (uint256) {
        return _active[index];
    }

    function activeBidIds() external view returns (uint256[] memory) {
        return _active;
    }

    function postBid(uint8 kind, uint256 param, uint256 unitPrice, uint256 qty, uint256 duration)
        external
        payable
        nonReentrant
        returns (uint256 bidId)
    {
        require(unitPrice > 0 && qty > 0, "price");
        require(duration >= MIN_DURATION && duration <= MAX_DURATION, "duration");
        if (kind == KIND_ANY) require(param == 0, "kind");
        else if (kind == KIND_CABIN) require(param <= 3, "kind");
        else if (kind == KIND_TOKEN) require(qty == 1, "qty");
        else revert("kind");

        uint256 total = unitPrice * qty;
        require(msg.value == total, "value");

        bidId = nextBidId++;
        uint64 expires = uint64(block.timestamp + duration);
        _bids[bidId] = Bid({
            buyer: msg.sender,
            unitPrice: unitPrice,
            qtyLeft: qty,
            kind: kind,
            param: param,
            expires: expires,
            open: true
        });
        _activate(bidId);
        emit BidPosted(bidId, msg.sender, kind, param, unitPrice, qty, expires);
    }

    /// @notice Seller fills one unit. Ticket must be approved for this market and still listable.
    function acceptBid(uint256 bidId, uint256 tokenId) external nonReentrant {
        Bid storage b = _bids[bidId];
        require(b.open, "closed");
        require(block.timestamp < b.expires, "expired");
        require(b.qtyLeft > 0, "closed");
        address owner = ticketNft.ownerOf(tokenId);
        require(owner == msg.sender, "not owner");
        require(_approved(owner, tokenId), "not approved");
        require(_listable(tokenId), "not listable");
        require(_matches(b.kind, b.param, tokenId), "mismatch");

        b.qtyLeft -= 1;
        if (b.qtyLeft == 0) _close(bidId);
        uint256 price = b.unitPrice;
        address buyer = b.buyer;
        (uint256 fee, uint256 proceeds) = MarketFee.split(price);
        ticketNft.transferFrom(owner, buyer, tokenId);
        _send(owner, proceeds);
        _send(feeRecipient, fee);
        emit BidFilled(bidId, tokenId, owner, buyer, price, fee, b.qtyLeft);
    }

    function cancelBid(uint256 bidId) external nonReentrant {
        Bid storage b = _bids[bidId];
        require(b.open, "closed");
        require(b.buyer == msg.sender, "not buyer");
        uint256 refund = b.unitPrice * b.qtyLeft;
        _close(bidId);
        _send(msg.sender, refund);
        emit BidCancelled(bidId, msg.sender, refund);
    }

    function refundExpired(uint256 bidId) external nonReentrant {
        Bid storage b = _bids[bidId];
        require(b.open, "closed");
        require(block.timestamp >= b.expires, "active");
        uint256 refund = b.unitPrice * b.qtyLeft;
        address buyer = b.buyer;
        _close(bidId);
        _send(buyer, refund);
        emit BidExpired(bidId, buyer, refund);
    }

    function _matches(uint8 kind, uint256 param, uint256 tokenId) internal view returns (bool) {
        if (kind == KIND_ANY) return true;
        if (kind == KIND_CABIN) return uint256(ticketNft.cabinOf(tokenId)) == param;
        return tokenId == param;
    }

    function _close(uint256 bidId) internal {
        Bid storage b = _bids[bidId];
        b.open = false;
        b.qtyLeft = 0;
        _deactivate(bidId);
    }

    function _activate(uint256 id) internal {
        _active.push(id);
        _pos[id] = _active.length;
    }

    function _deactivate(uint256 id) internal {
        uint256 pos = _pos[id];
        require(pos != 0, "index");
        uint256 lastId = _active[_active.length - 1];
        _active[pos - 1] = lastId;
        _pos[lastId] = pos;
        _active.pop();
        delete _pos[id];
    }

    function _send(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "pay");
    }
}
