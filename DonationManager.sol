// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title DonationManager
 * @dev Contract for managing and distributing donations among whitelisted receivers.
 */
contract DonationManager is IDonationManager, ReentrancyGuard {

    using ReflectionUtilities for address;
    using TransferUtilities for address;

    uint256 public constant ONE_HUNDRED = 1e18;

    uint256 public flushExecutorRewardPercentage;
    uint256 public executorRewardPercentage;

    uint256 public lastSplitBlock;
    uint256 public splitInterval;

    address[] public whitelistedReceivers;
    uint256[] public whitelistedPercentages;

    /**
     * @dev Constructor function for initializing the DonationManager contract.
     * @param initData Initialization data containing parameters for the contract.
     */
    constructor(bytes memory initData) {
        uint256 firstSplitBlock;
        (firstSplitBlock, splitInterval, whitelistedReceivers, whitelistedPercentages, flushExecutorRewardPercentage, executorRewardPercentage) = abi.decode(initData, (uint256, uint256, address[], uint256[], uint256, uint256));
        _setReceiversAndPercentages(whitelistedReceivers, whitelistedPercentages);
        lastSplitBlock = firstSplitBlock < splitInterval ? firstSplitBlock : (firstSplitBlock - splitInterval);
    }

    /**
     * @dev Fallback function that calls distributeDonations().
     */
    receive() external payable {
        distributeDonations();
    }

    function _supportsInterface(bytes4 interfaceId) internal pure returns(bool) {
        return
            interfaceId == this.ONE_HUNDRED.selector ||
            interfaceId == this.lastSplitBlock.selector ||
            interfaceId == this.splitInterval.selector ||
            interfaceId == this.nextSplitBlock.selector ||
            interfaceId == this.executorRewardPercentage.selector ||
            interfaceId == this.receiversAndPercentages.selector ||
            interfaceId == this.distributeDonations.selector;
    }

    /**
     * @dev Returns the block number for the next scheduled distribution.
     * @return The next scheduled distribution block number.
     */
    function nextSplitBlock() public view returns(uint256) {
        return lastSplitBlock == 0 ? 0 : (lastSplitBlock + splitInterval);
    }

    /**
     * @dev Returns the whitelisted receivers and their
     /**
     * @dev Returns the whitelisted receivers and their corresponding percentages.
     * @return receivers Array of whitelisted receiver addresses.
     * @return percentages Array of percentages for each whitelisted receiver.
     */
    function receiversAndPercentages() public view returns (address[] memory receivers, uint256[] memory percentages) {
        receivers = whitelistedReceivers;
        percentages = whitelistedPercentages;
    }

    /**
     * @dev Main contract function that distributes ETH among whitelisted receiver entities.
     * This function can be called once every splitInterval blocks by anyone.
     * The msg.sender is the executor of the function and takes a percentage of the distributed value.
     */
    function distributeDonations() public nonReentrant() {
        if (block.number < nextSplitBlock()){
            return;
        }

        uint256 availableAmount = address(this).balance;

        require(availableAmount > 0, "balance");

        uint256 receiverAmount = 0;

        if(executorRewardPercentage > 0) {
            address to = msg.sender;
            to.submit(receiverAmount = _calculatePercentage(availableAmount, executorRewardPercentage), "");
            availableAmount -= receiverAmount;
        }

        uint256 remainingAmount = availableAmount;

        (address[] memory addresses, uint256[] memory percentages) = receiversAndPercentages();

        require(addresses.length > 0);

        for(uint256 i = 0; i < addresses.length - 1; i++) {
            address receiver = addresses[i];
            require(receiver != address(0), "invalid address");
            receiverAmount = _calculatePercentage(availableAmount, percentages[i]);
            receiver.submit(receiverAmount, "");
            remainingAmount -= receiverAmount;
            emit DistributedDonation(receiver, receiverAmount, block.timestamp);
        }

        address finalReceiver = addresses[addresses.length - 1];
        require(finalReceiver != address(0), "invalid address");
        finalReceiver.submit(remainingAmount, "");

        lastSplitBlock = block.number;

        emit DistributedDonation(finalReceiver, remainingAmount, block.timestamp);
    }

    /**
     * @dev Helper function for calculating a percentage of a value.
     * @param totalSupply The total supply or value.
     * @param percentage The percentage to calculate.
     * @return The calculated percentage of the total supply.
     */
    function _calculatePercentage(uint256 totalSupply, uint256 percentage) private pure returns(uint256) {
        return (totalSupply * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    /**
     * @dev Helper function for setting whitelisted receivers and their percentages.
     * @param receivers Array of receiver addresses.
     * @param percentages Array of percentages for each receiver.
     */
    function _setReceiversAndPercentages(address[] memory receivers, uint256[] memory percentages) private {
        delete whitelistedReceivers;
        delete whitelistedPercentages;
        uint256 percentage = 0;
        if(receivers.length > 0) {
            for(uint256 i = 0; i < receivers.length - 1; i++) {
                whitelistedReceivers.push(receivers[i]);
                whitelistedPercentages.push(percentages[i]);
                percentage += percentages[i];
            }
            whitelistedReceivers.push(receivers[receivers.length - 1]);
        }
        require(percentage < ONE_HUNDRED, "overflow");
    }
}

/**
 * @title ReflectionUtilities
 * @dev Utility library.
 */

library ReflectionUtilities {

    function read(address subject, bytes memory inputData) internal view returns(bytes memory returnData) {
        bool result;
        (result, returnData) = subject.staticcall(inputData);
        if(!result) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

    function submit(address subject, uint256 value, bytes memory inputData) internal returns(bytes memory returnData) {
        bool result;
        (result, returnData) = subject.call{value : value}(inputData);
        if(!result) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

}
/**
 * @title TransferUtilities
 * @dev Utility library.
 */

library TransferUtilities {
    using ReflectionUtilities for address;

    function balanceOf(address erc20TokenAddress, address account) internal view returns(uint256) {
        if(erc20TokenAddress == address(0)) {
            return account.balance;
        }
        return abi.decode(erc20TokenAddress.read(abi.encodeWithSelector(IERC20(erc20TokenAddress).balanceOf.selector, account)), (uint256));
    }

    function allowance(address erc20TokenAddress, address account, address spender) internal view returns(uint256) {
        if(erc20TokenAddress == address(0)) {
            return 0;
        }
        return abi.decode(erc20TokenAddress.read(abi.encodeWithSelector(IERC20(erc20TokenAddress).allowance.selector, account, spender)), (uint256));
    }

    function safeApprove(address erc20TokenAddress, address spender, uint256 value) internal {
        bytes memory returnData = erc20TokenAddress.submit(0, abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, spender, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'APPROVE_FAILED');
    }

    function safeTransfer(address erc20TokenAddress, address to, uint256 value) internal {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            to.submit(value, "");
            return;
        }
        bytes memory returnData = erc20TokenAddress.submit(0, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal {
        if(value == 0) {
            return;
        }
        if(erc20TokenAddress == address(0)) {
            to.submit(value, "");
            return;
        }
        bytes memory returnData = erc20TokenAddress.submit(0, abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFERFROM_FAILED');
    }
}
