// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NFTMarket is ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(address => EnumerableSet.UintSet) private nftContractTokens;
    mapping(address => mapping(uint256 => Listing)) private listings;
    EnumerableSet.AddressSet private listedContractAddresses;

    IERC20 public immutable paymentToken;

    event NFTListed(address indexed seller, address indexed nftContract, uint256 indexed tokenId, uint256 price);
    event NFTPurchased(address indexed buyer, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price);
    event NFTUnlisted(address indexed seller, address indexed nftContract, uint256 indexed tokenId);

    constructor(address _paymentToken) {
        require(_paymentToken != address(0), "Invalid payment token address");
        paymentToken = IERC20(_paymentToken);
    }

    function listNFT(address _nftContract, uint256 _tokenId, uint256 _price) external {
        require(_price > 0, "Price must be greater than zero");
        IERC721 nftContract = IERC721(_nftContract);
        require(nftContract.ownerOf(_tokenId) == msg.sender, "Not the owner of this NFT");
        require(nftContract.getApproved(_tokenId) == address(this), "Contract is not approved");

        listings[_nftContract][_tokenId] = Listing(msg.sender, _price);
        nftContractTokens[_nftContract].add(_tokenId);
        listedContractAddresses.add(_nftContract);

        emit NFTListed(msg.sender, _nftContract, _tokenId, _price);
    }

    function unlistNFT(address _nftContract, uint256 _tokenId) external {
        require(listings[_nftContract][_tokenId].seller == msg.sender, "Not the seller of this NFT");

        delete listings[_nftContract][_tokenId];
        nftContractTokens[_nftContract].remove(_tokenId);
        if (nftContractTokens[_nftContract].length() == 0) {
            listedContractAddresses.remove(_nftContract);
        }

        emit NFTUnlisted(msg.sender, _nftContract, _tokenId);
    }

    function buyNFT(address _nftContract, uint256 _tokenId) external nonReentrant {
        Listing memory listing = listings[_nftContract][_tokenId];
        require(listing.seller != address(0), "NFT not listed for sale");
        require(listing.seller != msg.sender, "Cannot buy your own NFT");

        require(paymentToken.transferFrom(msg.sender, listing.seller, listing.price), "Payment failed");

        IERC721(_nftContract).safeTransferFrom(listing.seller, msg.sender, _tokenId);

        delete listings[_nftContract][_tokenId];
        nftContractTokens[_nftContract].remove(_tokenId);
        if (nftContractTokens[_nftContract].length() == 0) {
            listedContractAddresses.remove(_nftContract);
        }

        emit NFTPurchased(msg.sender, listing.seller, _nftContract, _tokenId, listing.price);
    }

    function isNFTListed(address _nftContract, uint256 _tokenId) external view returns (bool) {
        return nftContractTokens[_nftContract].contains(_tokenId);
    }

    function getAllListedNFTs(uint256 start, uint256 limit) external view returns (
        address[] memory nftContracts,
        uint256[] memory tokenIds,
        address[] memory sellers,
        uint256[] memory prices
    ) {
        uint256 totalListed = getTotalListedNFTs();
        uint256 resultLength = (start + limit > totalListed) ? totalListed - start : limit;

        nftContracts = new address[](resultLength);
        tokenIds = new uint256[](resultLength);
        sellers = new address[](resultLength);
        prices = new uint256[](resultLength);

        uint256 currentIndex = 0;
        uint256 listedCount = 0;

        for (uint256 i = 0; i < listedContractAddresses.length() && currentIndex < resultLength; i++) {
            address nftContract = listedContractAddresses.at(i);
            uint256[] memory tokens = nftContractTokens[nftContract].values();
            
            for (uint256 j = 0; j < tokens.length && currentIndex < resultLength; j++) {
                if (listedCount >= start) {
                    uint256 tokenId = tokens[j];
                    Listing memory listing = listings[nftContract][tokenId];
                    nftContracts[currentIndex] = nftContract;
                    tokenIds[currentIndex] = tokenId;
                    sellers[currentIndex] = listing.seller;
                    prices[currentIndex] = listing.price;
                    currentIndex++;
                }
                listedCount++;
            }
        }
    }

    function getTotalListedNFTs() public view returns (uint256 total) {
        for (uint256 i = 0; i < listedContractAddresses.length(); i++) {
            address nftContract = listedContractAddresses.at(i);
            total += nftContractTokens[nftContract].length();
        }
    }
}