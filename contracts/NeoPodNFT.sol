// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./base/ERC721Initializable.sol";
import "./base/OwnableInitializable.sol";
import "./common/StorageAccessible.sol";
import "./common/Singleton.sol";

/**
 * @title NeoPodNFT
 * @author Anoy Roy Chowdhury
 * @notice This contract manages four types of ERC721 NFTs for the NeoPod platform.
 * It includes role-based access for admins and minters and allows for a unique
 * metadata URI for each NFT type.
 */
contract NeoPodNFT is
    Singleton,
    StorageAccessible,
    ERC721Initializable,
    OwnableInitializable
{
    // Counter to keep track of the next token ID to be minted.
    uint256 private _tokenIdCounter;

    // Flag to prevent re-initialization
    bool private initialized;

    // Enum to define the four distinct types of NFTs.
    enum NFTType {
        Initiate,
        Sentinel,
        Operator,
        Architect
    }

    // Mapping from token ID to its NFT type.
    mapping(uint256 => NFTType) public tokenType;

    // Mapping to track which token ID a user holds for a specific NFT type.
    // This is crucial for targeted burning.
    // user address => NFTType => tokenId
    mapping(address => mapping(NFTType => uint256)) public ownedToken;

    // Mappings to manage admin and minter roles.
    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isMinter;

    // Mapping to store a unique base URI for each NFT type.
    mapping(NFTType => string) public typeURIs;

    // --- Events ---
    event AdminAdded(address indexed newAdmin);
    event AdminRemoved(address indexed removedAdmin);
    event MinterAdded(address indexed newMinter);
    event MinterRemoved(address indexed removedMinter);
    event NFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        NFTType nftType
    );
    event NFTBurned(
        address indexed from,
        uint256 indexed tokenId,
        NFTType nftType
    );
    event NFTUpgraded(
        address indexed user,
        uint256 burnedTokenId,
        NFTType burnedType,
        uint256 mintedTokenId,
        NFTType mintedType
    );
    event TypeURIUpdated(NFTType indexed nftType, string newURI);
    event SingletonUpdated(
        address indexed oldSingleton,
        address indexed newSingleton,
        address indexed admin
    );

    // --- Modifiers ---
    /**
     * @notice Throws if called by any account other than an admin.
     */
    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Caller is not an admin");
        _;
    }

    /**
     * @notice Throws if called by any account that is not an admin or a minter.
     */
    modifier onlyAdminOrMinter() {
        require(
            isAdmin[msg.sender] || isMinter[msg.sender],
            "Caller is not an admin or minter"
        );
        _;
    }

    constructor() {
        /**
         * By setting the initialized to true, it is not possible to call initialize anymore,
         * This is an unusable contract, and it is only used to deploy the proxy contract
         */
        initialized = true;
    }

    /**
     * @notice Initializes the contract.
     * @dev Can only be called once.
     * @param initialName The name of the token.
     * @param initialSymbol The symbol of the token.
     */
    function initialize(
        string memory initialName,
        string memory initialSymbol,
        address _owner
    ) external {
        require(!initialized, "Contract is already initialized");

        ERC721Initializable.initializeERC721(initialName, initialSymbol);
        OwnableInitializable.initializeOwnable(_owner);
        isAdmin[_owner] = true;
        emit AdminAdded(_owner);

        initialized = true;
    }

    // --- Role Management Functions ---

    /**
     * @notice Adds a new admin.
     * @dev Can only be called by an existing admin.
     * @param _newAdmin The address to grant admin privileges.
     */
    function addAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Invalid address");
        require(!isAdmin[_newAdmin], "Address is already an admin");
        isAdmin[_newAdmin] = true;
        emit AdminAdded(_newAdmin);
    }

    /**
     * @notice Removes an admin.
     * @dev Can only be called by an existing admin.
     * @param _adminToRemove The address to revoke admin privileges from.
     */
    function removeAdmin(address _adminToRemove) external onlyAdmin {
        require(isAdmin[_adminToRemove], "Address is not an admin");
        require(_adminToRemove != owner(), "Cannot remove the contract owner");
        isAdmin[_adminToRemove] = false;
        emit AdminRemoved(_adminToRemove);
    }

    /**
     * @notice Adds a new minter.
     * @dev Can only be called by an admin.
     * @param _newMinter The address to grant minter privileges.
     */
    function addMinter(address _newMinter) external onlyAdmin {
        require(_newMinter != address(0), "Invalid address");
        require(!isMinter[_newMinter], "Address is already a minter");
        isMinter[_newMinter] = true;
        emit MinterAdded(_newMinter);
    }

    /**
     * @notice Removes a minter.
     * @dev Can only be called by an admin.
     * @param _minterToRemove The address to revoke minter privileges from.
     */
    function removeMinter(address _minterToRemove) external onlyAdmin {
        require(isMinter[_minterToRemove], "Address is not a minter");
        isMinter[_minterToRemove] = false;
        emit MinterRemoved(_minterToRemove);
    }

    // --- URI Management ---

    /**
     * @notice Updates the base URI for a specific NFT type.
     * @param _nftType The type of NFT to update the URI for.
     * @param _uri The new base URI string. (e.g., "https://api.example.com/nfts/sentinel/")
     */
    function setTypeURI(
        NFTType _nftType,
        string memory _uri
    ) external onlyAdmin {
        typeURIs[_nftType] = _uri;
        emit TypeURIUpdated(_nftType, _uri);
    }

    /**
     * @notice Returns the URI for a given token ID.
     * @dev Constructs the URI by combining the type-specific base URI.
     */
    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        _requireOwned(_tokenId);
        NFTType nftType = tokenType[_tokenId];
        string memory baseURI = typeURIs[nftType];
        require(bytes(baseURI).length > 0, "URI not set for this NFT type");
        return baseURI;
    }

    // --- Core NFT Management Functions ---

    /**
     * @notice Mints a specific type of NFT to a given address.
     * @param _to The address that will receive the minted NFT.
     * @param _nftType The type of NFT to mint.
     */
    function mint(address _to, NFTType _nftType) external onlyAdminOrMinter {
        _mintNFT(_to, _nftType);
    }

    /**
     * @notice Burns a specific type of NFT from a given address.
     * @param _from The address whose NFT will be burned.
     * @param _nftType The type of NFT to burn.
     */
    function burn(address _from, NFTType _nftType) external onlyAdminOrMinter {
        uint256 tokenId = ownedToken[_from][_nftType];
        _burnNFT(_from, tokenId, _nftType);
    }

    /**
     * @notice Upgrades an NFT by burning one type and minting another.
     * @param _user The address of the user whose NFT is being upgraded.
     * @param _burnType The type of NFT to burn.
     * @param _mintType The type of NFT to mint.
     */
    function upgradeNFT(
        address _user,
        NFTType _burnType,
        NFTType _mintType
    ) external onlyAdminOrMinter {
        uint256 burnTokenId = ownedToken[_user][_burnType];
        _burnNFT(_user, burnTokenId, _burnType);
        uint256 mintTokenId = _mintNFT(_user, _mintType);

        emit NFTUpgraded(_user, burnTokenId, _burnType, mintTokenId, _mintType);
    }

    // --- Bulk NFT Management Functions ---

    /**
     * @notice Mints a specific type of NFT to multiple addresses.
     * @param _toList An array of addresses to receive the minted NFTs.
     * @param _nftType The type of NFT to mint.
     */
    function bulkMint(
        address[] calldata _toList,
        NFTType _nftType
    ) external onlyAdminOrMinter {
        for (uint i = 0; i < _toList.length; i++) {
            _mintNFT(_toList[i], _nftType);
        }
    }

    /**
     * @notice Burns a specific type of NFT from multiple addresses.
     * @param _fromList An array of addresses whose NFTs will be burned.
     * @param _nftType The type of NFT to burn.
     */
    function bulkBurn(
        address[] calldata _fromList,
        NFTType _nftType
    ) external onlyAdminOrMinter {
        for (uint i = 0; i < _fromList.length; i++) {
            uint256 tokenId = ownedToken[_fromList[i]][_nftType];
            if (tokenId != 0) {
                _burnNFT(_fromList[i], tokenId, _nftType);
            }
        }
    }

    /**
     * @notice Upgrades NFTs for multiple users by burning one type and minting another.
     * @param _userList An array of addresses for the upgrade.
     * @param _burnType The type of NFT to burn for each user.
     * @param _mintType The type of NFT to mint for each user.
     */
    function bulkUpgrade(
        address[] calldata _userList,
        NFTType _burnType,
        NFTType _mintType
    ) external onlyAdminOrMinter {
        for (uint i = 0; i < _userList.length; i++) {
            address user = _userList[i];
            uint256 burnTokenId = ownedToken[user][_burnType];
            if (burnTokenId != 0) {
                _burnNFT(user, burnTokenId, _burnType);
                uint256 mintTokenId = _mintNFT(user, _mintType);
                emit NFTUpgraded(
                    user,
                    burnTokenId,
                    _burnType,
                    mintTokenId,
                    _mintType
                );
            }
        }
    }

    // --- Internal Helper Functions ---

    /**
     * @dev Internal function to handle the core logic of minting an NFT.
     * @return The ID of the newly minted token.
     */
    function _mintNFT(
        address _to,
        NFTType _nftType
    ) internal returns (uint256) {
        require(_to != address(0), "ERC721: mint to the zero address");
        require(
            ownedToken[_to][_nftType] == 0,
            "User already holds this NFT type"
        );
        require(
            bytes(typeURIs[_nftType]).length > 0,
            "URI not set for this NFT type"
        );

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        _safeMint(_to, newTokenId);
        tokenType[newTokenId] = _nftType;
        ownedToken[_to][_nftType] = newTokenId;

        emit NFTMinted(_to, newTokenId, _nftType);
        return newTokenId;
    }

    /**
     * @dev Internal function to handle the core logic of burning an NFT.
     */
    function _burnNFT(
        address _from,
        uint256 _tokenId,
        NFTType _nftType
    ) internal {
        require(_tokenId != 0, "Token does not exist for this type");
        require(ownerOf(_tokenId) == _from, "Burner does not own this token");

        _burn(_tokenId);
        delete ownedToken[_from][_nftType];
        delete tokenType[_tokenId];

        emit NFTBurned(_from, _tokenId, _nftType);
    }

    // --- Singleton Management ---

    /**
     * @notice Updates the singleton (implementation) address
     * @dev Can only be called by an admin. This is a critical operation that changes the contract logic.
     * @param _newSingleton The new singleton/implementation address
     */
    function updateSingleton(address _newSingleton) external onlyAdmin {
        require(_newSingleton != address(0), "Invalid singleton address");
        require(_newSingleton != getSingleton(), "Same singleton address");
        require(_isContract(_newSingleton), "Singleton must be a contract");

        address oldSingleton = getSingleton();
        singleton = _newSingleton;

        emit SingletonUpdated(oldSingleton, _newSingleton, msg.sender);
    }

    /**
     * @notice Returns the current singleton address
     * @return The address of the current singleton/implementation contract
     */
    function getSingleton() public view returns (address) {
        return singleton;
    }

    /**
     * @notice Checks if an address is a contract
     * @param account The address to check
     * @return True if the address contains contract code
     */
    function _isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
