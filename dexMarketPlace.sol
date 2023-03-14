//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract  Marketplace is ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _itemsSold;
    Counters.Counter private _ItemCount;
    uint256 public LISTING_FEE = 0.0001 ether;
    address payable private _marketOwner;

    mapping(uint256 => ITEM) private _idToITEM;

    struct ITEM {
    uint256 itemId;
    address payable seller;
    address payable owner;
    uint256 price;
    bool listed;
  }

  event ITEMListed(
    uint256 itemId,
    address seller,
    address owner,
    uint256 price
  );

  event ITEMSold(
    uint256 itemId,
    address seller,
    address owner,
    uint256 price
  );

    uint256 marketRoyalties;
    mapping (address => uint256) private _sellerEscrowBalance;
    mapping (uint256 => bool) public _receivedPackage; //buyer

    constructor() {
    _marketOwner = payable(msg.sender);
  }

    modifier onlyMarketOwner(){
    require(msg.sender == _marketOwner, "You are not the Market Owner");
    _;
  }

   //    define the stable coins you want to accept here;
        
    ERC20 public paymentToken; //contract address of the specific token
    function setPayToken(ERC20 _paymentToken) public {
        paymentToken = _paymentToken;
    }

    function setMarketFees(uint256 _percentToSeller) public onlyMarketOwner nonReentrant {
        require (msg.sender == _marketOwner);
        marketRoyalties = _percentToSeller; //if market is working on royalties
    }

//Create Listing on Marketplace
    function listItem(uint256 _tokenId, uint256 _price) public payable nonReentrant {
    _tokenId = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, address(this))));
    require(_price > 0, "Price must be at least 1 wei");
    require(msg.value == LISTING_FEE, "Not enough ether for listing fee");

    _itemsSold.increment();

    _idToITEM[_tokenId] = ITEM(
      _tokenId, 
      payable(msg.sender),
      payable(address(this)),
      _price,
      true
    );

    emit ITEMListed(_tokenId, msg.sender, address(this), _price);
  }

  // Buy an NFT
    function buyItem(uint256 _tokenId, uint256 price) public payable nonReentrant {
    ITEM storage item = _idToITEM[_tokenId];
   // require(msg.value >= nft.price, "Not enough ether to cover asking price");
    require(price == item.price, "Enter the asking price");
    address payable buyer = payable(msg.sender);
    paymentToken.transferFrom(msg.sender, address(this), price);
    _sellerEscrowBalance[item.seller] += marketRoyalties*price;
  //  item.tokenId += item.buyer;
    _marketOwner.transfer(LISTING_FEE);
    item.owner = buyer;
    item.listed = false;
    _itemsSold.increment();
    emit ITEMSold(item.itemId, item.seller, buyer, msg.value);
  }

    function buyerConfirm(uint256 _tokenId, bool _status) public {
    require(msg.sender == _idToITEM[_tokenId].owner);
    _receivedPackage[_tokenId] = _status;
    } 


    function withdraw(uint256 _tokenId) public  nonReentrant {
    uint256 amount = _sellerEscrowBalance[msg.sender];
    require(amount > 0, "You have no funds to withdraw");
    require (_receivedPackage[_tokenId] = true, "Wait for Buyer's Confirmation");
    _sellerEscrowBalance[msg.sender] = 0;
    paymentToken.transferFrom(address(this), msg.sender, amount);
    }

    function getListingFee() public view returns (uint256) {
    return LISTING_FEE;
  }

    function getMarketItems() public view returns (ITEM[] memory) {
    uint256 itemCount = _ItemCount.current();
    uint256 unsoldItemsCount = itemCount - _itemsSold.current();

    ITEM[] memory items = new ITEM[](unsoldItemsCount);
    uint itemsIndex = 0;
    for (uint i = 0; i < itemCount; i++) {
      if (_idToITEM[i + 1].listed) {
        items[itemsIndex] = _idToITEM[i + 1];
        itemsIndex++;
      }
    }
    return items;
  }

    function getMyNfts() public view returns (ITEM[] memory) {
    uint itemCount = _ItemCount.current();
    uint myItemCount = 0;
    for (uint i = 0; i < itemCount; i++) {
      if (_idToITEM[i + 1].owner == msg.sender) {
        myItemCount++;
      }
    }

    ITEM[] memory items = new ITEM[](myItemCount);
    uint itemIndex = 0;
    for (uint i = 0; i < itemCount; i++) {
      if (_idToITEM[i + 1].owner == msg.sender) {
        items[itemIndex] = _idToITEM[i + 1];
        itemIndex++;
      }
    }
    return items;
  }

    function getMyListedItems() public view returns (ITEM[] memory) {
    uint itemCount = _ItemCount.current();
    uint myListedNftCount = 0;
    for (uint i = 0; i < itemCount; i++) {
      if (_idToITEM[i + 1].seller == msg.sender && _idToITEM[i + 1].listed) {
        myListedNftCount++;
      }
    }

    ITEM[] memory items = new ITEM[](myListedNftCount);
    uint itemsIndex = 0;
    for (uint i = 0; i < itemCount; i++) {
      if (_idToITEM[i + 1].seller == msg.sender && _idToITEM[i + 1].listed) {
        items[itemsIndex] = _idToITEM[i + 1];
        itemsIndex++;
      }
    }
    return items;
  }


}
