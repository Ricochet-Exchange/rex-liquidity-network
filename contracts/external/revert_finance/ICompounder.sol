// SPDX-License-Identifier: MIT
// This is a subset of ICompounder.sol from Revert.Finance's Compounder
// and is used in the tests to withdraw a token from the protocol
pragma solidity 0.8.18;


interface ICompoundor {
   
    /**
     * @notice Removes a NFT from the protocol and safe transfers it to address to
     * @param tokenId TokenId of token to remove
     * @param to Address to send to
     * @param withdrawBalances When true sends the available balances for token0 and token1 as well
     * @param data data which is sent with the safeTransferFrom call (optional)
     */
    function withdrawToken(
        uint256 tokenId,
        address to,
        bool withdrawBalances,
        bytes memory data
    ) external;



 
}