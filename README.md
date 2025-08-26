# NeoPod NFT Contracts

## Deployments
- Master Copy: [0x5C23F19b8A4a826FBd3Fe9475863D23EF2763c9D](https://xt4scan.ngd.network/address/0x5C23F19b8A4a826FBd3Fe9475863D23EF2763c9D?tab=contact_code)
- Proxy Factory: [0x07c26012e78E3343587a3d507a61A4EA3017782F](https://xt4scan.ngd.network/address/0x07c26012e78E3343587a3d507a61A4EA3017782F?tab=contact_code)
- Deployed Proxy: [0x07FEbE2BA75a89808156af7053EF22D23019178F](https://xt4scan.ngd.network/address/0x07FEbE2BA75a89808156af7053EF22D23019178F?tab=contract)

## 1\. Overview

This repository contains the Solidity smart contracts for the NeoPod NFT ecosystem. The system is designed to be robust, secure, and upgradable. It manages four distinct types of ERC721 Non-Fungible Tokens (NFTs) that represent different roles or statuses within the NeoPod platform.

The core of the system is built around an **upgradable proxy pattern**. This means we can fix bugs or add new features to the NFT logic in the future without changing the main contract address that users interact with, and without losing any data like NFT ownership.

The system is composed of three main contracts:

  * `NeoPodNFT.sol`: The implementation/logic contract that defines all the features of the NFT.
  * `Proxy.sol`: The storage contract that users interact with. It holds all the state (like who owns which NFT) and delegates logic calls to `NeoPodNFT.sol`.
  * `ProxyFactory.sol`: A helper contract to deploy new `Proxy` instances reliably and deterministically.

## 2\. System Architecture

### The Upgradable Proxy Pattern

To understand how these contracts work together, it's crucial to grasp the proxy pattern.

1.  **Separation of Logic and Storage:** We separate the contract's data (storage) from its rules (logic).

      * The `Proxy.sol` contract holds all the data (e.g., the mapping of token IDs to owners). It is the public-facing contract and its address never changes.
      * The `NeoPodNFT.sol` contract contains all the functions and logic (e.g., `mint`, `burn`, `transfer`).

2.  **`delegatecall`:** When a user calls a function on the `Proxy` contract, the `Proxy` uses a special EVM opcode called `delegatecall` to forward that call to the `NeoPodNFT` logic contract. `delegatecall` executes the code from the logic contract *in the context of the Proxy contract's storage*.

3.  **Upgradability:** To upgrade the contract, we simply deploy a new version of `NeoPodNFT.sol` and tell the `Proxy` contract to start using this new logic contract. All the data in the `Proxy` remains untouched.

### Architectural Diagram

```
+----------------+      Deploys      +---------------+
|                | ----------------> |               |
|  ProxyFactory  |                   |  Proxy        |
|                | <--- (Singleton)  |  (Storage)    |
+----------------+                   +---------------+
       ^                                    |
       |                                    | (Users interact with this address)
       |                                    |
+----------------+                          |
|      Owner     |                          | delegatecall()
+----------------+                          |
                                            V
                                   +------------------+
                                   |                  |
                                   |   NeoPodNFT      |
                                   |   (Logic)        |
                                   |                  |
                                   +------------------+
```

## 3\. Contract Details

### 1\. `NeoPodNFT.sol` (The Logic Contract)

This is the heart of the system, defining all the business logic for our NFTs.

**Key Features:**

  * **NFT Types**: Defines an `enum NFTType` for the four token categories: `Initiate`, `Sentinel`, `Operator`, and `Architect`.
  * **Role-Based Access Control**:
      * `owner`: The ultimate owner of the contract, set during initialization.
      * `isAdmin`: Admins can manage other admins, minters, and contract-level settings like URIs and the logic contract address. The owner is an admin by default.
      * `isMinter`: Minters have permission to mint NFTs. Admins are also considered minters.
  * **State Mappings**:
      * `tokenType`: Maps a `tokenId` to its `NFTType`.
      * `ownedToken`: Maps a user's address and an `NFTType` to the specific `tokenId` they own. This is crucial for efficiently finding and burning a user's specific NFT type.
  * **Core Functions**:
      * `initialize(...)`: Sets up the contract name, symbol, and initial owner. This function can only be called once on the proxy.
      * `mint(to, nftType)`: Mints a new NFT of a specific type to an address.
      * `burn(from, nftType)`: Burns a specific type of NFT from an address.
      * `upgradeNFT(user, burnType, mintType)`: Atomically burns one NFT type and mints another for a user.
  * **URI Management**:
      * `setTypeURI(nftType, uri)`: Allows an admin to set a unique base URI for each NFT type (e.g., `https://api.neopod.io/metadata/sentinel/`).
      * `tokenURI(tokenId)`: Automatically constructs the full metadata URI by appending the `tokenId` to the base URI for its type.
  * **Upgradability (`updateSingleton`)**:
      * An admin can call `updateSingleton(newAddress)` to point the proxy to a new logic contract implementation. This is the core upgrade mechanism.

### 2\. `Proxy.sol` (The Storage Contract)

This is a minimal, highly-optimized contract that serves as the stable, public entry point for the NeoPod NFT.

**How it works:**

  * **`singleton` Storage Variable:** The first storage slot (`slot 0`) stores the address of the current `NeoPodNFT` logic contract. It is crucial that this is the first variable declared in both the `Proxy` and `NeoPodNFT` contracts to ensure they occupy the same storage slot.
  * **`constructor(address _singleton)`**: When deployed by the `ProxyFactory`, it permanently sets the *initial* logic contract address.
  * **`fallback()` function**: This is the magic of the proxy. Any function call made to the `Proxy` contract that it doesn't recognize (which is all of them except the constructor) is caught by the `fallback` function. This function then:
    1.  Reads the `singleton` address from its storage.
    2.  Forwards the exact `calldata` (the function and arguments) to the `singleton` address using `delegatecall`.
    3.  Returns any data that the logic contract execution returns.
    4.  If the logic call reverts, the proxy also reverts.

### 3\. `ProxyFactory.sol` (The Deployment Contract)

This contract's sole purpose is to deploy new `Proxy` contracts in a secure and predictable manner.

**Key Features:**

  * **`CREATE2` Opcode**: It uses the `CREATE2` opcode for deployment. This allows us to calculate the final `Proxy` contract address *before* it is actually deployed on the blockchain. The address is determined by the factory's address, a `salt` (a unique number), and the proxy's creation bytecode.
  * **`deployProxy(singleton, initializer, salt)`**:
      * This is the main deployment function, restricted to the factory's `owner`.
      * `singleton`: The address of the deployed `NeoPodNFT` logic contract.
      * `initializer`: The encoded function call to `initialize(...)` the proxy contract immediately after deployment.
      * `salt`: A unique `bytes32` value to ensure a unique, predictable address.
  * **Address Calculation Functions**:
      * `calculateProxyAddress(singleton, salt)` and `calculateProxyAddressWithNonce(...)` are view functions that allow anyone to compute what the proxy's address will be without spending any gas. This is useful for off-chain systems that need to know the address in advance.

## 4\. How It Works: Key Flows

### Initial Deployment Flow

1.  **Deploy Logic Contract**: First, deploy the `NeoPodNFT.sol` contract to the blockchain. This will be our V1 implementation. Let's call its address `LOGIC_V1_ADDRESS`.
2.  **Deploy Factory**: Deploy the `ProxyFactory.sol` contract.
3.  **Deploy Proxy**: The owner of the `ProxyFactory` calls `deployProxy()` with:
      * `singleton`: `LOGIC_V1_ADDRESS`.
      * `initializer`: The encoded call to `NeoPodNFT.initialize("NeoPod NFT", "NEO", owner_address)`.
      * `salt`: A unique, chosen `bytes32` value.
4.  **Result**: A new `Proxy` contract is created at a deterministic address. It is now initialized and ready to be used. All future interactions will be with this `Proxy` address.

### Standard Interaction Flow (e.g., Minting)

1.  An admin or minter wants to mint a `Sentinel` NFT for Alice.
2.  They call the `mint(alice_address, NFTType.Sentinel)` function on the **`Proxy` contract address**.
3.  The `Proxy`'s `fallback` function is triggered.
4.  The `Proxy` executes a `delegatecall` to the `NeoPodNFT` logic contract, passing along the function signature and arguments.
5.  The `mint` function logic inside `NeoPodNFT` runs, but it modifies the storage of the `Proxy` contract.
6.  The `ownedToken` and `balanceOf` mappings inside the `Proxy`'s storage are updated. Alice now owns a new `Sentinel` token.

### Contract Upgrade Flow

1.  **Deploy New Logic**: A new, improved version of the logic is written (`NeoPodNFT_V2.sol`). It is compiled and deployed to the blockchain. Let's call its address `LOGIC_V2_ADDRESS`.
2.  **Admin Call**: An Admin calls the `updateSingleton(LOGIC_V2_ADDRESS)` function on the **`Proxy` contract address**.
3.  **Delegate Call**: The `Proxy` delegate-calls this function to the current logic contract (`NeoPodNFT_V1`).
4.  **Storage Update**: The `updateSingleton` function in `NeoPodNFT_V1` updates the `singleton` variable located at storage slot 0 inside the `Proxy` contract. The value is changed from `LOGIC_V1_ADDRESS` to `LOGIC_V2_ADDRESS`.
5.  **Upgrade Complete**: From this point on, any new call to the `Proxy` contract will be delegated to the `NeoPodNFT_V2` logic. All storage (NFT owners, balances, roles) is preserved as it was stored in the `Proxy` contract all along.

## 5\. Key Features & Concepts

### NFT Types

The contract supports four distinct types of NFTs, managed via the `NFTType` enum. This allows for clear, type-safe differentiation between roles on-chain.

  * `Initiate`
  * `Sentinel`
  * `Operator`
  * `Architect`

### Role-Based Access Control (RBAC)

Access to critical functions is restricted to prevent unauthorized actions.

  * **Owner**: The initial contract deployer/manager, has the highest level of control.
  * **Admins**: Can manage contract settings and roles. They can add/remove other admins and minters.
  * **Minters**: Are only allowed to mint, burn, and upgrade NFTs. This allows for separating operational roles from administrative ones.

### Deterministic Deployment with `CREATE2`

The `ProxyFactory` uses `CREATE2` to ensure that the address of a new proxy is predictable. This is powerful for system design, as front-ends and other smart contracts can know the NFT contract address before it's even created.

### Bulk Operations

The contract includes `bulkMint`, `bulkBurn`, and `bulkUpgrade` functions. These are essential for gas efficiency, as they allow an admin to perform the same action for a large list of users in a single transaction, significantly reducing the overall cost compared to individual transactions.