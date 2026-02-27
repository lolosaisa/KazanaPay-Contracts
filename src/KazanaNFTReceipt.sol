//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  KazanaNFTReceipt.sol
  - ERC721 receipts minted by merchant (owner) after successful payment.
  - Each token stores immutable payment proof fields and an editable metadataURI.
  - Owner-only minting and admin controls (pause / setBaseURI / updateMetadata).
*/

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract KazanaNFTReceipt is ERC721URIStorage, Ownable, Pausable {
    uint256 private _nextTokenId;

    // Receipt data stored on-chain (read-only for buyer/merchant fields)
    struct Receipt {
        address buyer;
        address merchant;
        uint256 amount;      // amount in smallest USDC unit (6 decimals)
        string txHash;       // original Base tx hash (string to support different explorers)
        string orderId;      // vendor order id (optional)
        uint256 timestamp;   // block.timestamp when minted
    }

    // tokenId => Receipt
    mapping(uint256 => Receipt) private _receipts;
    mapping(bytes32 => bool) private _usedTxHashes;

    // Events
    event ReceiptMinted(address indexed merchant, address indexed buyer, uint256 indexed tokenId, uint256 amount, string txHash, string orderId, string metadataURI);
    event MetadataUpdated(uint256 indexed tokenId, string metadataURI);
    event BaseURIUpdated(string baseURI);
    event TxHashConsumed(bytes32 indexed txHashKey, uint256 indexed tokenId);

    // constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
    //     _nextTokenId = 1; // start IDs at 1 (easier human handling)
    // }
    constructor(string memory name_, string memory symbol_)
    ERC721(name_, symbol_)
    Ownable(msg.sender)
{
    _nextTokenId = 1;
}

    // --- Modifiers ---
    // modifier onlyExistingToken(uint256 tokenId) {
    //     require(ownerOf(tokenId) != address(0), "NFTReceipt: token does not exist");
    //     _;
    // }
    modifier onlyExistingToken(uint256 tokenId) {
    require(ownerOf(tokenId) != address(0), "NFTReceipt: token does not exist");
    _;
}


    // --- Minting (owner-only) ---
    /**
     * @notice Mint a receipt NFT to `buyer`. Only callable by owner.
     * @param buyer Recipient address (customer).
     * @param merchant Merchant address receiving payment (for record).
     * @param amount Amount in smallest USDC unit (6 decimals).
     * @param txHash On-chain transaction hash used to pay the merchant.
     * @param orderId Optional merchant order id.
     * @param metadataURI Token metadata (IPFS/HTTP).
     */
    function mintReceipt(
        address buyer,
        address merchant,
        uint256 amount,
        string calldata txHash,
        string calldata orderId,
        string calldata metadataURI
    ) external onlyOwner whenNotPaused returns (uint256) {
        require(buyer != address(0), "NFTReceipt: buyer is zero address");
        require(merchant != address(0), "NFTReceipt: merchant is zero address");
        require(amount > 0, "NFTReceipt: amount must be > 0");
        require(bytes(txHash).length > 0, "NFTReceipt: txHash required");
        //Prevent duplicate minting
        
        bytes32 txHashKey = keccak256(bytes(txHash));
        require(!_usedTxHashes[txHashKey], "NFTReceipt: receipt already minted for this txHash");
        _usedTxHashes[txHashKey] = true;
        

        uint256 tokenId = _nextTokenId++;
        _safeMint(buyer, tokenId);
        _setTokenURI(tokenId, metadataURI);

        _receipts[tokenId] = Receipt({
            buyer: buyer,
            merchant: merchant,
            amount: amount,
            txHash: txHash,
            orderId: orderId,
            timestamp: block.timestamp
        });

        emit ReceiptMinted(merchant, buyer, tokenId, amount, txHash, orderId, metadataURI);
        emit TxHashConsumed(txHashKey, tokenId); // emit after tokenId is assigned


        return tokenId;
    }

    /// @notice helper function Returns true if a receipt has already been minted for this txHash
    function isTxHashUsed(string calldata txHash) external view returns (bool) {
        return _usedTxHashes[keccak256(bytes(txHash))];
        }

    // @dev Blocks all transfers except mint and burn — makes tokens soulbound. a transfer is valid only if it's a mint (from == address(0)) or a burn (to == address(0)). Any other case (wallet to wallet) gets blocked.
    function _update(address to, uint256 tokenId, address auth)
      internal
      override
    returns (address)
    {
      address from = _ownerOf(tokenId);
      require(
        from == address(0) || to == address(0),
        "NFTReceipt: soulbound token, transfers are disabled"
        );
    return super._update(to, tokenId, auth);
    }


    // --- Read helpers ---
    function getReceipt(uint256 tokenId) external view onlyExistingToken(tokenId) returns (Receipt memory) {
        return _receipts[tokenId];
    }
    
    function verifyReceipt(uint256 tokenId, address buyer) public view onlyExistingToken(tokenId) returns (bool) {
    return _receipts[tokenId].buyer == buyer;
   }




    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // --- Metadata update (owner-only) ---
    /**
     * @notice Update token URI if metadata needs to be repinned or corrected.
     * Only owner can call.
     */
    function updateMetadataURI(uint256 tokenId, string calldata metadataURI) external onlyOwner onlyExistingToken(tokenId) {
        _setTokenURI(tokenId, metadataURI);
        emit MetadataUpdated(tokenId, metadataURI);
    }

    // --- Admin / pause controls ---
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --- Optional: set base URI for tokens minted with relative URIs ---
    function _baseURI() internal view virtual override returns (string memory) {
        return super._baseURI();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // --- Burn (optional, onlyOwner) - if you want to revoke receipts ---
    function burn(uint256 tokenId) external onlyOwner onlyExistingToken(tokenId) {
        _burn(tokenId);
        // deleting mapping to save UX (not strictly necessary)
        delete _receipts[tokenId];
    }
}
