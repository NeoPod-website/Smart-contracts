// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "./Proxy.sol";

/**
 * @title ProxyFactory
 * @notice Factory contract for deploying Proxy instances
 * @dev Enhanced version with better error handling, events, and public interface
 */
contract ProxyFactory {
    // Events for transparency and indexing
    event ProxyDeployed(
        address indexed proxy,
        address indexed singleton,
        bytes32 salt,
        address deployer
    );

    // Custom errors for gas efficiency and better UX
    error SingletonNotDeployed();
    error ProxyDeploymentFailed();
    error InitializationFailed();
    error InvalidOwner();
    error InvalidSingleton();

    /**
     * @notice Deploys a new Proxy with specified parameters
     * @param singleton The implementation contract address
     * @param initializer Initialization call data
     * @param salt Unique salt for deterministic address generation
     * @return proxy The deployed proxy address
     */
    function deployProxy(
        address singleton,
        bytes memory initializer,
        bytes32 salt
    ) public returns (Proxy proxy) {
        // Input validation
        if (!isContract(singleton)) revert SingletonNotDeployed();

        // Prepare deployment data
        bytes memory deploymentData = abi.encodePacked(
            type(Proxy).creationCode,
            abi.encode(singleton)
        );

        // Deploy using CREATE2
        assembly {
            proxy := create2(
                0x0,
                add(0x20, deploymentData),
                mload(deploymentData),
                salt
            )
        }

        // Check deployment success
        if (address(proxy) == address(0)) revert ProxyDeploymentFailed();

        // Initialize if initializer provided
        if (initializer.length > 0) {
            assembly {
                if eq(
                    call(
                        gas(),
                        proxy,
                        0,
                        add(initializer, 0x20),
                        mload(initializer),
                        0,
                        0
                    ),
                    0
                ) {
                    revert(0, 0)
                }
            }
        }

        emit ProxyDeployed(address(proxy), singleton, salt, msg.sender);
    }

    /**
     * @notice Deploys a proxy with auto-generated salt based on sender and nonce
     * @param singleton The implementation contract address
     * @param initializer Initialization call data
     * @param nonce Nonce for salt generation
     * @return proxy The deployed proxy address
     */
    function deployProxyWithNonce(
        address singleton,
        bytes memory initializer,
        uint256 nonce
    ) external returns (Proxy proxy) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, nonce));
        return deployProxy(singleton, initializer, salt);
    }

    /**
     * @notice Calculates the deterministic address of a proxy before deployment
     * @param singleton The implementation contract address
     * @param salt Salt for deterministic address generation
     * @return proxyAddress The calculated proxy address
     */
    function calculateProxyAddress(
        address singleton,
        bytes32 salt
    ) external view returns (address proxyAddress) {
        bytes memory deploymentData = abi.encodePacked(
            type(Proxy).creationCode,
            abi.encode(singleton)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(deploymentData)
            )
        );

        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Calculates proxy address using sender and nonce
     * @param singleton The implementation contract address
     * @param nonce Nonce for salt generation
     * @param deployer The address that will deploy the proxy
     * @return proxyAddress The calculated proxy address
     */
    function calculateProxyAddressWithNonce(
        address singleton,
        uint256 nonce,
        address deployer
    ) external view returns (address proxyAddress) {
        bytes32 salt = keccak256(abi.encodePacked(deployer, nonce));
        return this.calculateProxyAddress(singleton, salt);
    }

    /**
     * @notice Checks if a proxy exists at the calculated address
     * @param singleton The implementation contract address
     * @param salt Salt used for deployment
     * @return exists True if proxy exists at calculated address
     */
    function proxyExists(
        address singleton,
        bytes32 salt
    ) external view returns (bool exists) {
        address calculatedAddress = this.calculateProxyAddress(singleton, salt);
        return isContract(calculatedAddress);
    }

    /**
     * @notice Returns true if `account` is a contract.
     * @dev This function will return false if invoked during the constructor of a contract,
     * as the code is not actually created until after the constructor finishes.
     * @param account The address being queried
     * @return True if `account` is a contract
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @notice Gets the creation code hash for proxy address calculation
     * @dev Useful for off-chain address calculation
     * @return hash The creation code hash
     */
    function getProxyCreationCodeHash() external pure returns (bytes32 hash) {
        return keccak256(type(Proxy).creationCode);
    }
}
