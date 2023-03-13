# Donation-Manager
The DonationsManager contract is designed to collect ETH and distribute it in equal proportions to whitelisted ONG addresses. 
The smart contract is connected to a web app dashboard and is a Proof of Concept (POC) that Urbe.eth will showcase at "The common-good side of web3" event organized by Veracura and Urbe.eth in Rome (Wegil) on 25/03/2023.

The POC aims to highlight some of the powerful properties of the intersection between web3 technology and the ONG world, such as:
- automation: distributing donations every x unix time set
- autonomous execution: anyone can call the distributeDonations function to distrubute ETH when the time arrives, and they will be rewarded with a % of the split ETH amount
- decentralized permissions: once the contract is deployed and initialized no one can stop receiving or distributing ETH or change whitelisted ONG addresses. No one can change the permissions initially set

The DonationsManager.sol code implements the IDonationManager interface and contains the following functions:

- nextSplitBlock: returns the next unix time for a donation split.
- receiversAndPercentages: returns the whitelisted ONG receivers and their corresponding percentages.
- distributeDonations: the main function that splits ETH among the whitelisted ONG entities. This function can only be called once every splitInterval unix time by anyone. The msg.sender is the executor of the function, and it takes a percentage of the split value.
- flushETH: sends the contract's balance to an emergency wallet address in case of an emergency. This function can only be called by the initially set emergency wallet address.

The DonationsManager contract has the following state variables:

- flushExecutorRewardPercentage: the percentage of the contract balance to be given to the executor when flushing ETH.
- executorRewardPercentage: the percentage of the contract balance to be given to the executor when distributing donations.
- lastSplitBlock: the unix time of the last donation split.
- splitInterval: unix time interval between each donation split.
- whitelistedReceivers: an array of addresses for the whitelisted receivers.
- whitelistedPercentages: an array of percentages for the whitelisted receivers.
- emergencyReceiver: the address of the emergency wallet.
