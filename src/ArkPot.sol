// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITicketView {
    function isSurvivor(uint256 tokenId) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
    function survivorCount() external view returns (uint256);
}

/// @title ArkPot — locked prize pot shared by day-100 survivors.
/// @dev No owner withdraw/rescue. Only receive + claimShare after landfall.
///      `land` does not scan tickets and does not take an id list. TicketNFT keeps the survivor
///      counter (settled cabin, not sunk). A claim checks that id itself. Rounding dust (and any
///      BNB that arrives after land) is paid to the last claim so it does not sit forever.
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

    /// @notice FloodEngine only, after night 100 is fully settled. O(1): the NFT holds the count.
    function land() external nonReentrant {
        require(msg.sender == floodEngine, "not flood");
        require(!landed, "landed");
        require(address(ticketNft) != address(0), "no nft");

        uint256 n = ticketNft.survivorCount();
        require(n > 0, "survivors");

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
}
