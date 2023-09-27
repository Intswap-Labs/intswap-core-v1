// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

contract IntswapV1Permision is Ownable {
    bool public isGlobalOnlyEOA = true;
    bool public isPaused;

    struct Permision {
        bool isOnlyEOA;
        bool isOnlyOwner;
        bool isWhitelist;
        mapping(address => mapping(bytes32 => bool)) whitelist;
        mapping(address => mapping(bytes32 => bool)) blacklist;
    }

    mapping(address => Permision) public permisions;

    function setGlobalOnlyEOA(bool _isGlobalOnlyEOA) external onlyOwner {
        isGlobalOnlyEOA = _isGlobalOnlyEOA;
    }

    function setPaused(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
    }

    function setPermision(address called, bool _isOnlyEOA, bool _isOnlyOwner, bool _isWhitelist) external onlyOwner {
        Permision storage _permision = permisions[called];
        _permision.isOnlyEOA = _isOnlyEOA;
        _permision.isOnlyOwner = _isOnlyOwner;
        _permision.isWhitelist = _isWhitelist;
    }

    function setBlacklist(address called, address[] memory accounts, bytes32[] memory functionSigs, bool[] memory status) external onlyOwner {
        Permision storage _permision = permisions[called];
        for (uint i; i < accounts.length; i++) {
            _permision.blacklist[accounts[i]][functionSigs[i]] = status[i];
        }
    }

    function setWhitelist(address called, address[] memory accounts, bytes32[] memory functionSigs, bool[] memory status) external onlyOwner {
        Permision storage _permision = permisions[called];
        for (uint i; i < accounts.length; i++) {
            _permision.whitelist[accounts[i]][functionSigs[i]] = status[i];
        }
    }

    function isAllowedToCall(address called, address caller, bytes32 action) external view returns(bool) {
        if (isPaused) {
            return false;
        }
        
        if (isGlobalOnlyEOA && tx.origin != caller) {
            return false;
        }

        Permision storage _permision = permisions[called];
        if (_permision.isOnlyEOA && tx.origin != caller) {
            return false;
        }

        if (_permision.isOnlyOwner && caller != owner()) {
            return false;
        }

        if (_permision.isWhitelist && !_permision.whitelist[caller][action]) {
            return false;
        }

        if (_permision.blacklist[caller][action]) {
            return false;
        }

        return true;
    }
}
