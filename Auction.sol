//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";

contract AuctionFactory{
    Auction[] public auctions;

    function createAuction() public{
        Auction newAuction = new Auction(msg.sender);
        auctions.push(newAuction);
    }
}

contract Auction is ReentrancyGuard{
    using SafeMath for uint256;

    address payable public owner;
    address payable public highestBidder;
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public highestBindingBid;
    uint256 bidIncrement;

    modifier notOwner(){
        require(msg.sender != owner);
        _;
    }

    modifier afterStart(){
        require(block.number >= startBlock);
        _;
    }

    modifier beforeEnd(){
        require(block.number <= endBlock);
        _;
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    mapping(address => uint256) public bids;

    enum State {Started, Running, Ended, Canceled}
    State public auctionState;

    constructor(address _eoa){
        owner = payable(_eoa);
        auctionState = State.Running;
        startBlock = block.number;
        endBlock = startBlock.add(40320); // will end in one week
        bidIncrement = 100; 
    }

    function cancelAuction() public onlyOwner{
        auctionState = State.Canceled;
    }

    function placeBid() public payable notOwner afterStart beforeEnd {
        require(auctionState == State.Running);
        require(msg.value >= 100);

        uint256 currentBid = bids[msg.sender].add(msg.value);
        require(currentBid > highestBindingBid);

        bids[msg.sender] = currentBid;

        if(currentBid <= bids[highestBidder]){
            highestBindingBid = min(currentBid.add(bidIncrement), bids[highestBidder]);
        }else{
            highestBindingBid = min(currentBid, bids[highestBidder].add(bidIncrement));
            highestBidder = payable(msg.sender);
        }
    }

    function min(uint256 a, uint256 b) pure internal returns(uint256) {
        return (a <= b) ? a : b;
    }

    function finalizeAuction() public nonReentrant{
        require(auctionState == State.Canceled || block.number > endBlock);
        require(msg.sender == owner || bids[msg.sender] > 0);

        address payable recipient;
        uint256 value;

        if(auctionState == State.Canceled){
            recipient = payable(msg.sender);
            value = bids[msg.sender];
        }else{ // auction ended (not canceled)
            if(msg.sender == owner){ 
                recipient = owner;
                value = highestBindingBid;
            }else{ // this is a bidder
                if(msg.sender == highestBidder){
                    recipient = highestBidder;
                    value = bids[highestBidder].sub(highestBindingBid);
                }else{ // this is neither the owner nor the highestBidder
                    recipient = payable(msg.sender);
                    value = bids[msg.sender];
                }
            }
        }

        //reset the bids of the recipient to 0
        bids[recipient] = 0;

        // send value to the recipient
        recipient.transfer(value);
    }
}
