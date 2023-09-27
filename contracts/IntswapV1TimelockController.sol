// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IntswapV1TimelockController is TimelockController, Ownable {
    uint256 public constant minDelay = 1 days;
    address public creatorManager;
    
    event NewCreatorManager(address oldCreatorManager, address newCreatorManager);

    constructor(
        address[] memory proposers,
        address[] memory executors  
    )
        TimelockController(
            minDelay,
            proposers,
            executors
        )
    {
        _grantRole(CANCELLER_ROLE, _msgSender());
    }

    function updateCreatorManager(address _creatorManager) external onlyOwner {
        address oldCreatorManager = creatorManager;
        creatorManager = _creatorManager;

        if (oldCreatorManager != address(0)) {
            _revokeRole(PROPOSER_ROLE, oldCreatorManager);
            _revokeRole(CANCELLER_ROLE, oldCreatorManager);
            _revokeRole(EXECUTOR_ROLE, oldCreatorManager);
        }

        _grantRole(PROPOSER_ROLE, creatorManager);
        _grantRole(CANCELLER_ROLE, creatorManager);
        _grantRole(EXECUTOR_ROLE, creatorManager);

        emit NewCreatorManager(oldCreatorManager, _creatorManager);
    }
}
