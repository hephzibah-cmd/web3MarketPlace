// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import "./whiteListAndInspectors.sol";

/////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////


/*
TO BE ADDED:
1. TIMELOCK
2. REFUND
3.
*/


/////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////

contract Marketplace is ReentrancyGuard /*, Whitelist*/ {
  using Counters for Counters.Counter;
  Counters.Counter private _nftsSold;
  Counters.Counter private _nftCount;
  uint256 public LISTING_FEE = 0.0001 ether;
  address payable private _marketOwner;
  mapping(uint256 => NFT) private _idToNFT;
  struct NFT {
    address nftContract;
    uint256 tokenId;
    address payable seller;
    address payable owner;
    uint256 price;
    bool listed;
  }
  

  event NFTListed(
    address nftContract,
    uint256 tokenId,
    address seller,
    address owner,
    uint256 price
  );

  event NFTSold(
    address nftContract,
    uint256 tokenId,
    address seller,
    address owner,
    uint256 price
  );

    uint256 marketRoyalties;
    mapping (address => uint256) private _sellerEscrowBalance;
    mapping (uint256 => address) public _inspectorForSale;
    mapping (address => uint256) public _tokenToInspect;
    mapping (uint256 => bool) public _saleSuccess; //inspector
    mapping (uint256 => bool) public _receivedPackage; //buyer
    mapping (address => uint256) public _successfulConfirmations;//the number of confirmations an inspector has made


    address [] public inspectorAddresses;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public inspectors;

    event AddressAdded(address indexed _address);
    event AddressRemoved(address indexed _address);

    event InspectorAdded(address indexed _address);
    event InspectorRemoved(address indexed _address);
    event InspectorForMySale(uint _tokenId, address _inspectorAddress);

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Seller address is not whitelisted");
        _;
    }

    modifier onlyInspector() {
        require(inspectors[msg.sender], "You are Not an Inspector");
        _;
    }

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

  // List the NFT on the marketplace
  function listNft(address _nftContract, uint256 _tokenId, uint256 _price) public payable onlyWhitelisted nonReentrant {
    require(_price > 0, "Price must be at least 1 wei");
    require(msg.value == LISTING_FEE, "Not enough ether for listing fee");

    IERC721(_nftContract).transferFrom(msg.sender, address(this), _tokenId);

    _nftCount.increment();

    _idToNFT[_tokenId] = NFT(
      _nftContract,
      _tokenId, 
      payable(msg.sender),
      payable(address(this)),
      _price,
      true
    );

    emit NFTListed(_nftContract, _tokenId, msg.sender, address(this), _price);
  }

  // Resell an NFT purchased from the marketplace
  function resellNft(address _nftContract, uint256 _tokenId, uint256 _price) public payable onlyWhitelisted nonReentrant {
    require(msg.value == LISTING_FEE, "Not enough funds for listing fee");

    IERC721(_nftContract).transferFrom(msg.sender, address(this), _tokenId);

    NFT storage nft = _idToNFT[_tokenId];
    nft.seller = payable(msg.sender);
    nft.owner = payable(address(this));
    nft.listed = true;
    nft.price = _price;
    
    _nftsSold.decrement();
    emit NFTListed(_nftContract, _tokenId, msg.sender, address(this), _price);
  }

  // Buy an NFT
  function buyNft(address _nftContract, uint256 _tokenId, uint256 price) public payable nonReentrant {
    NFT storage nft = _idToNFT[_tokenId];
   // require(msg.value >= nft.price, "Not enough ether to cover asking price");
    require(price == nft.price, "Enter the asking price");

    // get number of inspectors from external contract
    uint numInspectors = getNumInspectors();

    //randomly select one
    uint randomNum = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % numInspectors;
    address selectedInspector = inspectorAddresses[randomNum];
    _inspectorForSale[_tokenId] = selectedInspector;
    _tokenToInspect[selectedInspector] =_tokenId;

    address payable buyer = payable(msg.sender);
    //payable(nft.seller).transfer(msg.value);
    //_sellerEscrowBalance[nft.seller] += msg.value;
    paymentToken.transferFrom(msg.sender, address(this), price);
    _sellerEscrowBalance[nft.seller] += price;

    IERC721(_nftContract).transferFrom(address(this), buyer, nft.tokenId);
    _marketOwner.transfer(LISTING_FEE);
    nft.owner = buyer;
    nft.listed = false;

    _nftsSold.increment();
    emit NFTSold(_nftContract, nft.tokenId, nft.seller, buyer, msg.value);
    emit InspectorForMySale(_tokenId, selectedInspector);
  }

    function buyerConfirm(uint256 _tokenId, bool _status) public {
       require(msg.sender == _idToNFT[_tokenId].owner);
        _receivedPackage[_tokenId] = _status;
    } 
    
    function confirmSaleSuccess(uint256 _tokenId, bool _passed) public {
    require(_inspectorForSale[_tokenId] == msg.sender || _marketOwner == msg.sender, "You are not the assigned inspector for this sale"); // added a functionality for the market owner to verify sales in case the inspector goes off
    delete _inspectorForSale[_tokenId];
    _saleSuccess[_tokenId] = _passed;
    _successfulConfirmations[msg.sender] ++;

    }

    function withdraw(uint256 _tokenId) public onlyWhitelisted nonReentrant {
    uint256 amount = _sellerEscrowBalance[msg.sender];
    require(amount > 0, "You have no funds to withdraw");

    // Check that the buyer has confirmed the sale success
    //require(_inspectorForSale[_idToNFT[_tokenId]] == address(0), "Sale has not been confirmed as successful");
    require (_saleSuccess[_tokenId]);
    // Transfer the funds to the seller
    _sellerEscrowBalance[msg.sender] = 0;
    //payable(msg.sender).transfer(amount);
    paymentToken.transferFrom(address(this), msg.sender, amount);
    }
  
  function getListingFee() public view returns (uint256) {
    return LISTING_FEE;
  }

  function getListedNfts() public view returns (NFT[] memory) {
    uint256 nftCount = _nftCount.current();
    uint256 unsoldNftsCount = nftCount - _nftsSold.current();

    NFT[] memory nfts = new NFT[](unsoldNftsCount);
    uint nftsIndex = 0;
    for (uint i = 0; i < nftCount; i++) {
      if (_idToNFT[i + 1].listed) {
        nfts[nftsIndex] = _idToNFT[i + 1];
        nftsIndex++;
      }
    }
    return nfts;
  }

  function getMyNfts() public view returns (NFT[] memory) {
    uint nftCount = _nftCount.current();
    uint myNftCount = 0;
    for (uint i = 0; i < nftCount; i++) {
      if (_idToNFT[i + 1].owner == msg.sender) {
        myNftCount++;
      }
    }

    NFT[] memory nfts = new NFT[](myNftCount);
    uint nftsIndex = 0;
    for (uint i = 0; i < nftCount; i++) {
      if (_idToNFT[i + 1].owner == msg.sender) {
        nfts[nftsIndex] = _idToNFT[i + 1];
        nftsIndex++;
      }
    }
    return nfts;
  }

  function getMyListedNfts() public view returns (NFT[] memory) {
    uint nftCount = _nftCount.current();
    uint myListedNftCount = 0;
    for (uint i = 0; i < nftCount; i++) {
      if (_idToNFT[i + 1].seller == msg.sender && _idToNFT[i + 1].listed) {
        myListedNftCount++;
      }
    }

    NFT[] memory nfts = new NFT[](myListedNftCount);
    uint nftsIndex = 0;
    for (uint i = 0; i < nftCount; i++) {
      if (_idToNFT[i + 1].seller == msg.sender && _idToNFT[i + 1].listed) {
        nfts[nftsIndex] = _idToNFT[i + 1];
        nftsIndex++;
      }
    }
    return nfts;
  }

  function getInspector(uint _tokenId) public view returns (address){
    return _inspectorForSale[_tokenId];
  }

  function doIHaveInspection(address _myAddress) public view returns (uint){
    return _tokenToInspect[_myAddress];

  }

  function myInspections()public view returns(uint) {
    return _successfulConfirmations[msg.sender] * 1;
  }

   function addInspector(address _address) public {
        
        require(_address != address(0), "Invalid address");
        require(!inspectors[_address], "Address is already an Inspector");
        inspectorAddresses.push(_address);
        inspectors[_address] = true;
        emit InspectorAdded(_address);
    }

    function removeInspector(address _address) public {
        require(whitelist[_address], "Address is not an Inspector");
        inspectors[_address] = false;

        //find the index and delete
        uint index;
        for (uint i = 0; i <inspectorAddresses.length; i++){
            if (inspectorAddresses[i] == _address){
                index = i;
                break;
            }
        }
        //delete inspectorAddresses[index];
        for (uint i = index; i <inspectorAddresses.length -1; i++){
            inspectorAddresses[i] = inspectorAddresses[i+i];
        }

        inspectorAddresses.pop();

        emit InspectorRemoved(_address);
    }

        function addAddress(address _address) public {
        require(_address != address(0), "Invalid address");
        require(!whitelist[_address], "Address is already whitelisted");
        whitelist[_address] = true;
        emit AddressAdded(_address);
    }

    function removeAddress(address _address) public {
        require(whitelist[_address], "Address is not whitelisted");
        whitelist[_address] = false;
        emit AddressRemoved(_address);
    }

    function isWhitelisted(address _address) public view returns (bool) {
    return whitelist[_address];
    }

    function isInspector(address _address) public view returns (bool) {
    return inspectors[_address];
    }

    function getNumInspectors() public view returns (uint) {
        return inspectorAddresses.length;
    }
}
