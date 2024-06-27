// SPDX-License-Identifier: MIT
// LabelFactory.sol
pragma solidity ^0.8.20;

import "./FeeManager.sol";
import "./LabelOwnershipToken.sol";
import "./Releaser.sol";

contract LabelFactory {
    FeeManager public feeManager;
    LabelOwnershipToken public immutable labelOwnershipToken;

    event LabelCreated(address indexed releaserAddress, string labelName, uint256 labelOwnershipTokenId);

    constructor(address _feeManagerAddress) {
        feeManager = FeeManager(_feeManagerAddress);
        labelOwnershipToken = new LabelOwnershipToken(address(this));
    }

    function createLabel(
        string memory labelName, 
        uint256 initialReleaseFee, 
        uint256 initialRequiredEthAmount,
        bool initialOnlyLabelOwnerCanCreate
    ) external returns (address) {
        require(feeManager.feeToken().transferFrom(msg.sender, feeManager.owner(), feeManager.launchFee()), "Launch fee transfer failed");

        uint256 labelOwnershipTokenId = labelOwnershipToken.mint(msg.sender);

        Releaser newReleaser = new Releaser(
            address(feeManager.feeToken()),
            initialReleaseFee,
            feeManager.uniswapFactory(),
            labelName,
            address(labelOwnershipToken),
            labelOwnershipTokenId,
            initialRequiredEthAmount,
            initialOnlyLabelOwnerCanCreate,
            feeManager.swapTokenAddress()
        );

        emit LabelCreated(address(newReleaser), labelName, labelOwnershipTokenId);
        return address(newReleaser);
    }
}