// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TicketMarketBNB} from "../../src/TicketMarketBNB.sol";
import {TicketMarketARK} from "../../src/TicketMarketARK.sol";
import {TicketBidMarket} from "../../src/TicketBidMarket.sol";

contract MockTicket {
    struct Ticket {
        uint8 cabin;
        uint64 lastClaim;
        uint64 mintedAt;
        address minter;
        uint64 cabinCommitBlock;
    }

    mapping(uint256 => address) internal _owner;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(uint256 => Ticket) public tickets;

    function mint(address to, uint256 id) external {
        require(_owner[id] == address(0), "exists");
        _owner[id] = to;
        tickets[id] = Ticket({
            cabin: 0,
            lastClaim: uint64(block.timestamp),
            mintedAt: uint64(block.timestamp),
            minter: to,
            cabinCommitBlock: 0
        });
    }

    function ownerOf(uint256 id) external view returns (address) {
        address o = _owner[id];
        require(o != address(0), "no");
        return o;
    }

    function approve(address spender, uint256 id) external {
        require(_owner[id] == msg.sender, "not owner");
        getApproved[id] = spender;
    }

    function setApprovalForAll(address operator, bool ok) external {
        isApprovedForAll[msg.sender][operator] = ok;
    }

    function transferFrom(address from, address to, uint256 id) external {
        address o = _owner[id];
        require(o == from && to != address(0), "owner");
        require(msg.sender == from || getApproved[id] == msg.sender || isApprovedForAll[from][msg.sender], "auth");
        _owner[id] = to;
        getApproved[id] = address(0);
    }

    function isAlive(uint256 id) public view returns (bool) {
        Ticket memory t = tickets[id];
        return t.mintedAt != 0 && t.cabin != 4;
    }

    function cabinOf(uint256 id) external view returns (uint8) {
        return tickets[id].cabin;
    }

    function setCabin(uint256 id, uint8 cabin) external {
        tickets[id].cabin = cabin;
    }

    function setCommit(uint256 id, uint64 commitBlock) external {
        tickets[id].cabinCommitBlock = commitBlock;
    }
}

contract MockArk {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Takes 10% of every transferFrom so the ARK market must reject it.
contract TaxArk {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - amount / 10;
        return true;
    }
}

contract ReenterSeller {
    MockTicket public immutable nft;
    TicketMarketBNB public immutable market;
    uint256 public secondId;
    bool internal _entered;
    uint256 public nestedOk;

    constructor(MockTicket nft_, TicketMarketBNB market_) {
        nft = nft_;
        market = market_;
    }

    function approveAndList(uint256 id, uint256 price) external {
        nft.approve(address(market), id);
        market.list(id, price);
    }

    function arm(uint256 id) external {
        secondId = id;
    }

    receive() external payable {
        if (secondId != 0 && !_entered) {
            _entered = true;
            try market.buy{value: 1 ether}(secondId) {
                nestedOk = 1;
            } catch {
                nestedOk = 2;
            }
        }
    }
}

contract TicketMarketTest is Test {
    address fee = makeAddr("fee");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    MockTicket tickets;
    MockArk ark;
    TicketMarketBNB bnb;
    TicketMarketARK arkMarket;

    function setUp() public {
        tickets = new MockTicket();
        ark = new MockArk();
        bnb = new TicketMarketBNB(address(tickets), fee);
        arkMarket = new TicketMarketARK(address(tickets), address(ark), fee);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function _err(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function _mintApproved(uint256 id, address market) internal {
        tickets.mint(alice, id);
        vm.prank(alice);
        tickets.approve(market, id);
    }

    function test_feeBps_andQuote() public {
        assertEq(bnb.MARKET_FEE_BPS(), 250);
        assertEq(arkMarket.MARKET_FEE_BPS(), 250);
        _mintApproved(1, address(bnb));
        vm.prank(alice);
        bnb.list(1, 1 ether);
        (uint256 price, uint256 cut, uint256 proceeds) = bnb.quote(1);
        assertEq(price, 1 ether);
        assertEq(cut, 0.025 ether);
        assertEq(proceeds, 0.975 ether);
        (uint256 dustFee, uint256 dustProceeds) = bnb.feeOn(1);
        assertEq(dustFee, 0);
        assertEq(dustProceeds, 1);
    }

    function test_constructor_rejectsZero() public {
        vm.expectRevert(_err("zero"));
        new TicketMarketBNB(address(0), fee);
        vm.expectRevert(_err("zero"));
        new TicketMarketBNB(address(tickets), address(0));
        vm.expectRevert(_err("zero"));
        new TicketMarketARK(address(tickets), address(0), fee);
    }

    function test_listBuyCancel_feeAndOverpay() public {
        _mintApproved(1, address(bnb));
        vm.prank(alice);
        bnb.list(1, 1 ether);
        assertTrue(bnb.buyable(1));
        assertTrue(bnb.listable(1));

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        bnb.buy{value: 1.2 ether}(1);

        assertEq(tickets.ownerOf(1), bob);
        assertEq(fee.balance, 0.025 ether);
        assertEq(alice.balance, aliceBefore + 0.975 ether);
        assertEq(bob.balance, bobBefore - 1 ether);
        assertEq(address(bnb).balance, 0);
        assertEq(bnb.listingCount(), 0);

        vm.prank(bob);
        vm.expectRevert(_err("unlisted"));
        bnb.buy{value: 1 ether}(1);
    }

    function test_cancel_clearsBook_nftStays() public {
        _mintApproved(1, address(bnb));
        _mintApproved(2, address(bnb));
        vm.startPrank(alice);
        bnb.list(1, 1 ether);
        bnb.list(2, 2 ether);
        bnb.cancel(1);
        vm.stopPrank();
        assertEq(bnb.listingCount(), 1);
        assertEq(bnb.listingIdAt(0), 2);
        assertEq(tickets.ownerOf(1), alice);
        vm.prank(bob);
        vm.expectRevert(_err("unlisted"));
        bnb.buy{value: 1 ether}(1);
    }

    function test_rejectsSunk_andPendingCabin_allowsUnsettled() public {
        tickets.mint(alice, 1);
        tickets.setCabin(1, 4);
        vm.prank(alice);
        tickets.approve(address(bnb), 1);
        vm.prank(alice);
        vm.expectRevert(_err("not listable"));
        bnb.list(1, 1 ether);

        tickets.mint(alice, 2);
        tickets.setCommit(2, uint64(block.number + 5));
        vm.prank(alice);
        tickets.approve(address(bnb), 2);
        vm.prank(alice);
        vm.expectRevert(_err("not listable"));
        bnb.list(2, 1 ether);

        _mintApproved(3, address(bnb));
        assertEq(tickets.cabinOf(3), 0);
        vm.prank(alice);
        bnb.list(3, 1 ether);
        assertTrue(bnb.listable(3));
    }

    function test_buyRejectsSunkOrCabinRequest_thenClean() public {
        _mintApproved(1, address(bnb));
        vm.prank(alice);
        bnb.list(1, 1 ether);
        tickets.setCabin(1, 4);
        assertFalse(bnb.buyable(1));
        vm.prank(bob);
        vm.expectRevert(_err("not listable"));
        bnb.buy{value: 1 ether}(1);
        bnb.cleanListing(1);
        assertEq(bnb.listingCount(), 0);

        _mintApproved(2, address(bnb));
        vm.prank(alice);
        bnb.list(2, 1 ether);
        tickets.setCommit(2, uint64(block.number + 5));
        vm.prank(bob);
        vm.expectRevert(_err("not listable"));
        bnb.buy{value: 1 ether}(2);
        bnb.cleanListing(2);
        assertEq(bnb.listingCount(), 0);
    }

    function test_cleanLiveReverts_staleApprovalCleans() public {
        _mintApproved(1, address(bnb));
        vm.prank(alice);
        bnb.list(1, 1 ether);
        vm.expectRevert(_err("live"));
        bnb.cleanListing(1);
        vm.prank(alice);
        tickets.approve(address(0), 1);
        assertFalse(bnb.buyable(1));
        bnb.cleanListing(1);
        assertEq(bnb.listingCount(), 0);
    }

    function test_buyRejectsStaleOwner() public {
        _mintApproved(1, address(bnb));
        vm.prank(alice);
        bnb.list(1, 1 ether);
        vm.prank(alice);
        tickets.transferFrom(alice, bob, 1);
        vm.prank(bob);
        tickets.approve(address(bnb), 1);
        vm.prank(bob);
        vm.expectRevert(_err("stale"));
        bnb.buy{value: 1 ether}(1);
        bnb.cleanListing(1);
    }

    function test_underpayAndNotSeller() public {
        _mintApproved(1, address(bnb));
        vm.prank(bob);
        vm.expectRevert(_err("not owner"));
        bnb.list(1, 1 ether);
        vm.prank(alice);
        bnb.list(1, 1 ether);
        vm.prank(bob);
        vm.expectRevert(_err("underpay"));
        bnb.buy{value: 0.5 ether}(1);
        assertEq(bnb.listingCount(), 1);
        vm.prank(bob);
        vm.expectRevert(_err("not seller"));
        bnb.cancel(1);
    }

    function test_operatorApproval_andCabinRides() public {
        tickets.mint(alice, 1);
        tickets.setCabin(1, 2);
        vm.prank(alice);
        tickets.setApprovalForAll(address(bnb), true);
        vm.prank(alice);
        bnb.list(1, 1 ether);
        vm.prank(bob);
        bnb.buy{value: 1 ether}(1);
        assertEq(tickets.ownerOf(1), bob);
        assertEq(tickets.cabinOf(1), 2);
        (uint8 cabin,, uint64 mintedAt,, uint64 commit) = tickets.tickets(1);
        assertEq(cabin, 2);
        assertGt(mintedAt, 0);
        assertEq(commit, 0);
    }

    function test_reentrancyOnPayout_doesNotFillSecondListing() public {
        ReenterSeller seller = new ReenterSeller(tickets, bnb);
        vm.deal(address(seller), 5 ether);
        tickets.mint(address(seller), 1);
        tickets.mint(address(seller), 2);
        seller.approveAndList(1, 1 ether);
        seller.approveAndList(2, 1 ether);
        seller.arm(2);
        vm.prank(bob);
        bnb.buy{value: 1 ether}(1);
        assertEq(seller.nestedOk(), 2);
        assertEq(tickets.ownerOf(1), bob);
        assertEq(tickets.ownerOf(2), address(seller));
        assertEq(bnb.listingCount(), 1);
        assertEq(bnb.listingIdAt(0), 2);
    }

    function test_arkBuy_fee_noBnb_rejectsTaxToken() public {
        assertEq(arkMarket.MARKET_FEE_BPS(), 250);
        _mintApproved(1, address(arkMarket));
        vm.prank(alice);
        arkMarket.list(1, 1_000 ether);
        ark.mint(bob, 1_000 ether);
        vm.prank(bob);
        ark.approve(address(arkMarket), 1_000 ether);
        vm.prank(bob);
        vm.expectRevert(_err("no bnb"));
        arkMarket.buy{value: 1}(1);
        vm.prank(bob);
        arkMarket.buy(1);
        assertEq(tickets.ownerOf(1), bob);
        assertEq(ark.balanceOf(bob), 0);
        assertEq(ark.balanceOf(alice), 975 ether);
        assertEq(ark.balanceOf(fee), 25 ether);
        assertEq(ark.balanceOf(address(arkMarket)), 0);

        TaxArk taxed = new TaxArk();
        TicketMarketARK bad = new TicketMarketARK(address(tickets), address(taxed), fee);
        tickets.mint(alice, 2);
        vm.prank(alice);
        tickets.approve(address(bad), 2);
        vm.prank(alice);
        bad.list(2, 100 ether);
        taxed.mint(bob, 100 ether);
        vm.prank(bob);
        taxed.approve(address(bad), 100 ether);
        vm.prank(bob);
        vm.expectRevert(_err("tax"));
        bad.buy(2);
        assertEq(tickets.ownerOf(2), alice);
    }
}

contract TicketBidTest is Test {
    address fee = makeAddr("fee");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    MockTicket tickets;
    TicketBidMarket bids;

    function setUp() public {
        tickets = new MockTicket();
        bids = new TicketBidMarket(address(tickets), fee);
        vm.deal(alice, 50 ether);
        vm.deal(bob, 50 ether);
    }

    function _err(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function _hold(address who, uint256 id, uint8 cabin) internal {
        tickets.mint(who, id);
        if (cabin != 0) tickets.setCabin(id, cabin);
        vm.prank(who);
        tickets.approve(address(bids), id);
    }

    function test_feeAndPostRules() public {
        assertEq(bids.MARKET_FEE_BPS(), 250);
        vm.prank(bob);
        vm.expectRevert(_err("qty"));
        bids.postBid{value: 2 ether}(2, 7, 1 ether, 2, 1 hours);
        vm.prank(bob);
        vm.expectRevert(_err("kind"));
        bids.postBid{value: 1 ether}(0, 1, 1 ether, 1, 1 hours);
        vm.prank(bob);
        vm.expectRevert(_err("kind"));
        bids.postBid{value: 1 ether}(1, 4, 1 ether, 1, 1 hours);
        vm.prank(bob);
        vm.expectRevert(_err("duration"));
        bids.postBid{value: 1 ether}(0, 0, 1 ether, 1, 1 hours - 1);
        vm.prank(bob);
        vm.expectRevert(_err("value"));
        bids.postBid{value: 1 ether}(0, 0, 1 ether, 2, 1 hours);

        vm.prank(bob);
        uint256 id = bids.postBid{value: 3 ether}(0, 0, 1 ether, 3, 30 days);
        assertEq(id, 1);
        assertEq(address(bids).balance, 3 ether);
        (address buyer, uint256 unitPrice, uint256 qtyLeft, uint8 kind,, uint64 expires, bool open) = bids.bidOf(1);
        assertEq(buyer, bob);
        assertEq(unitPrice, 1 ether);
        assertEq(qtyLeft, 3);
        assertEq(kind, 0);
        assertTrue(open);
        assertEq(expires, uint64(block.timestamp + 30 days));
    }

    function test_fillPartial_fee_thenCancelRefundsRest() public {
        _hold(alice, 1, 1);
        vm.prank(bob);
        bids.postBid{value: 3 ether}(0, 0, 1 ether, 3, 1 days);
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        bids.acceptBid(1, 1);
        assertEq(tickets.ownerOf(1), bob);
        assertEq(tickets.cabinOf(1), 1);
        assertEq(alice.balance, aliceBefore + 0.975 ether);
        assertEq(fee.balance, 0.025 ether);
        (,, uint256 left,,,, bool open) = bids.bidOf(1);
        assertEq(left, 2);
        assertTrue(open);

        vm.prank(alice);
        vm.expectRevert(_err("not buyer"));
        bids.cancelBid(1);
        vm.prank(bob);
        bids.cancelBid(1);
        assertEq(bob.balance, bobBefore + 2 ether);
        assertEq(address(bids).balance, 0);
        assertEq(bids.bidCount(), 0);
        (,,,,,, bool still) = bids.bidOf(1);
        assertFalse(still);
    }

    function test_cabinAndTokenKinds_rejectSunkAndPending() public {
        _hold(alice, 1, 1);
        _hold(alice, 2, 2);
        vm.prank(bob);
        bids.postBid{value: 1 ether}(1, 2, 1 ether, 1, 1 hours);
        vm.prank(alice);
        vm.expectRevert(_err("mismatch"));
        bids.acceptBid(1, 1);
        vm.prank(alice);
        bids.acceptBid(1, 2);
        assertEq(tickets.ownerOf(2), bob);

        _hold(alice, 3, 0);
        vm.prank(bob);
        bids.postBid{value: 1 ether}(2, 9, 1 ether, 1, 1 hours);
        vm.prank(alice);
        vm.expectRevert(_err("mismatch"));
        bids.acceptBid(2, 3);

        tickets.mint(alice, 9);
        vm.prank(alice);
        tickets.approve(address(bids), 9);
        vm.prank(alice);
        bids.acceptBid(2, 9);
        assertEq(tickets.ownerOf(9), bob);

        _hold(alice, 4, 4);
        vm.prank(bob);
        bids.postBid{value: 1 ether}(0, 0, 1 ether, 1, 1 hours);
        vm.prank(alice);
        vm.expectRevert(_err("not listable"));
        bids.acceptBid(3, 4);

        _hold(alice, 5, 1);
        tickets.setCommit(5, uint64(block.number + 5));
        vm.prank(bob);
        bids.postBid{value: 1 ether}(0, 0, 1 ether, 1, 1 hours);
        vm.prank(alice);
        vm.expectRevert(_err("not listable"));
        bids.acceptBid(4, 5);
    }

    function test_expiryRefund_andActiveSwap() public {
        vm.startPrank(bob);
        bids.postBid{value: 1 ether}(0, 0, 1 ether, 1, 1 hours);
        bids.postBid{value: 2 ether}(1, 1, 1 ether, 2, 2 hours);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        vm.expectRevert(_err("expired"));
        bids.acceptBid(1, 1);

        uint256 bobBefore = bob.balance;
        bids.refundExpired(1);
        assertEq(bob.balance, bobBefore + 1 ether);
        assertEq(bids.bidCount(), 1);
        assertEq(bids.bidIdAt(0), 2);

        vm.expectRevert(_err("active"));
        bids.refundExpired(2);
        vm.prank(bob);
        bids.cancelBid(2);
        assertEq(bids.bidCount(), 0);
        assertEq(address(bids).balance, 0);
    }
}
