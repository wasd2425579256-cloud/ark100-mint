// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITicketView {
    function isSurvivor(uint256 tokenId) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
    function totalMinted() external view returns (uint256);
}

/// @title ArkPot — locked prize pot shared by day-100 survivors.
/// @dev No owner withdraw/rescue. Only receive + claimShare after landfall.
///      `land` does not trust a partial caller list: the survivor count is scanned from the NFT,
///      every id must be a unique survivor, and the list length must equal that scan. Rounding dust
///      (and any BNB that arrives after land) is paid to the last claim so it does not sit forever.
contract ArkPot is ReentrancyGuard {
    address public immutable deployer;
    address public sale;
    address public floodEngine;
    ITicketView public ticketNft;

    bool public landed;
    uint256 public landfallTimestamp;
    uint256 public survivorCount;
    uint256 public sharePerTicket;
    uint256 public claimsPaid;
    mapping(uint256 => bool) public claimed;

    event SaleSet(address sale);
    event FloodEngineSet(address flood);
    event TicketNftSet(address nft);
    event Landed(uint256 survivors, uint256 potBalance, uint256 sharePerTicket);
    event ShareClaimed(uint256 indexed tokenId, address indexed to, uint256 amount);
    event BnbReceived(address indexed from, uint256 amount);

    constructor() {
        deployer = msg.sender;
    }

    function setSale(address sale_) external {
        require(msg.sender == deployer, "not deployer");
        require(sale == address(0) && sale_ != address(0), "set");
        sale = sale_;
        emit SaleSet(sale_);
    }

    function setFloodEngine(address flood) external {
        require(msg.sender == deployer, "not deployer");
        require(floodEngine == address(0) && flood != address(0), "set");
        floodEngine = flood;
        emit FloodEngineSet(flood);
    }

    function setTicketNft(address nft) external {
        require(msg.sender == sale, "not sale");
        require(address(ticketNft) == address(0) && nft != address(0), "set");
        ticketNft = ITicketView(nft);
        emit TicketNftSet(nft);
    }

    receive() external payable {
        emit BnbReceived(msg.sender, msg.value);
    }

    function land(uint256[] calldata survivorIds) external nonReentrant {
        require(msg.sender == floodEngine, "not flood");
        require(!landed, "landed");
        require(address(ticketNft) != address(0), "no nft");

        uint256 minted = ticketNft.totalMinted();
        uint256 n;
        for (uint256 id = 1; id <= minted; ++id) {
            if (ticketNft.isSurvivor(id)) n++;
        }
        require(n > 0 && survivorIds.length == n, "survivors");

        // id => seen bit. One-time write; not cleared.
        for (uint256 i; i < n; ++i) {
            uint256 id = survivorIds[i];
            require(id >= 1 && id <= minted, "id");
            require(ticketNft.isSurvivor(id), "not survivor");
            require(!_seen(id), "dup");
            _mark(id);
        }

        landed = true;
        landfallTimestamp = block.timestamp;
        survivorCount = n;
        sharePerTicket = address(this).balance / n;
        emit Landed(n, address(this).balance, sharePerTicket);
    }

    function claimShare(uint256 tokenId) external nonReentrant {
        require(landed, "not landed");
        require(!claimed[tokenId], "claimed");
        require(ticketNft.isSurvivor(tokenId), "not survivor");
        address owner_ = ticketNft.ownerOf(tokenId);
        require(msg.sender == owner_, "not owner");
        claimed[tokenId] = true;
        claimsPaid += 1;
        // Equal shares, with the leftover wei (and anything received after land) on the last claim.
        uint256 amount = claimsPaid == survivorCount ? address(this).balance : sharePerTicket;
        (bool ok,) = owner_.call{value: amount}("");
        require(ok, "pay fail");
        emit ShareClaimed(tokenId, owner_, amount);
    }

    mapping(uint256 => uint256) private _bits;

    function _seen(uint256 id) internal view returns (bool) {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 255);
        return (_bits[word] & bit) != 0;
    }

    function _mark(uint256 id) internal {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 255);
        _bits[word] |= bit;
    }
}
