// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DonationManager is IDonationManager {

    using ReflectionUtilities for address;
    using TransferUtilities for address;

    uint256 public constant ONE_HUNDRED = 1e18;

    uint256 public flushExecutorRewardPercentage;
    uint256 public executorRewardPercentage;

    uint256 public lastSplitBlock;
    uint256 public splitInterval;

    address[] public whitelistedReceivers;
    uint256[] public whitelistedPercentages;
    address public emergencyReceiver;

    //Constructor init
    constructor(bytes memory initData) {
        uint256 firstSplitBlock;
        (firstSplitBlock, splitInterval, whitelistedReceivers, whitelistedPercentages, emergencyReceiver, flushExecutorRewardPercentage, executorRewardPercentage) = abi.decode(initData, (uint256, uint256, address[], uint256[], address, uint256, uint256));
        _setReceiversAndPercentages(whitelistedReceivers, whitelistedPercentages);
        lastSplitBlock = firstSplitBlock < splitInterval ? firstSplitBlock : (firstSplitBlock - splitInterval);
    }

    receive() external payable {
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

    function nextSplitBlock() public view returns(uint256) {
        return lastSplitBlock == 0 ? 0 : (lastSplitBlock + splitInterval);
    }

    function receiversAndPercentages() public view returns (address[] memory receivers, uint256[] memory percentages) {
        receivers = whitelistedReceivers;
        percentages = whitelistedPercentages;
    }

    //main contract function. It splits ETH among whitelisted ONG entities
    //this function can be called once every splitInterval blocks by anyone
    //the msg.sender is the executor of the function and it takes a percentage of the split value
    function distributeDonations() external {
        require(block.number >= nextSplitBlock(), "too early");
        lastSplitBlock = block.number;

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
        
        address receiver;
        for(uint256 i = 0; i < addresses.length - 1; i++) {
            receiver = addresses[i];
            receiver = receiver != address(0) ? receiver : emergencyReceiver;
            receiverAmount = _calculatePercentage(availableAmount, percentages[i]);
            receiver.submit(receiverAmount, "");
            emit DistributedDonation(receiver, receiverAmount, block.timestamp);
            remainingAmount -= receiverAmount;
        }

        receiver = addresses[addresses.length - 1];
        receiver = receiver != address(0) ? receiver : emergencyReceiver;
        receiver.submit(remainingAmount, "");
        emit DistributedDonation(receiver, remainingAmount, block.timestamp);
    }

    function flushETH() external {
        address to = msg.sender;
        address wallet = emergencyReceiver;
        require(wallet != address(0), "zero");

        uint256 availableAmount = address(this).balance;
        require(availableAmount > 0, "value");

        address tokenAddress = address(0);

        if(flushExecutorRewardPercentage > 0) {
            uint256 receiverAmount = _calculatePercentage(availableAmount, flushExecutorRewardPercentage);
            tokenAddress.safeTransfer(to, receiverAmount);
            availableAmount -= receiverAmount;
        }
        tokenAddress.safeTransfer(wallet, availableAmount);
    }

    function _calculatePercentage(uint256 totalSupply, uint256 percentage) private pure returns(uint256) {
        return (totalSupply * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

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

    function isContract(address subject) internal view returns (bool) {
        if(subject == address(0)) {
            return false;
        }
        uint256 codeLength;
        assembly {
            codeLength := extcodesize(subject)
        }
        return codeLength > 0;
    }

    function clone(address originalContract) internal returns(address copyContract) {
        assembly {
            mstore(
                0,
                or(
                    0x5880730000000000000000000000000000000000000000803b80938091923cF3,
                    mul(originalContract, 0x1000000000000000000)
                )
            )
            copyContract := create(0, 0, 32)
            switch extcodesize(copyContract)
                case 0 {
                    invalid()
                }
        }
    }
}

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