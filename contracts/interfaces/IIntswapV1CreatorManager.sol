// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIntswapV1CreatorManager {
    function isNFTOwner(address nft, address account) external view returns(bool);
}