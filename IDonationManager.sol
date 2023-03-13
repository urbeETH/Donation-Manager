// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IDonationManager {
    event DistributedDonation(address indexed whitelistedReceiver, uint256 amount, uint256 distributionBlock);
    event EmergencyWithdrawn(address indexed emergencyReceiver, uint256 amount, uint256 distributionBlock);
}