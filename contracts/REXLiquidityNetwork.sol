// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Gelato Network Imports
import "./external/gelato/AutomateTaskCreator.sol";

// Uniswap Imports
import "./external/uniswap/interfaces/ISwapRouter02.sol";
import "./external/uniswap/interfaces/INonfungiblePositionManager.sol";

// WMATIC
import "./external/wmatic/IWMATIC.sol";

import "hardhat/console.sol";


contract REXLiquidityNetwork is AutomateTaskCreator {


    struct PositionState {
        uint256 tokensOwed0;
        uint256 tokensOwed1;
        uint256 tokensForGelato0;
        uint256 tokensForGelato1;
        address token0;
        address token1;
        uint24 fee;
    }

    uint256 public constant INTERVAL = 60; // The interval for gelato to check for execution
    uint128 public constant GELATO_FEE_SHARE = 1; // 1% of the collected fees go to Gelato
    uint24 public constant UNISWAP_FEE = 500; // 0.05% Uniswap V3 Fee
    address public constant WRAPPED_GAS_TOKEN =
        0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // WMATIC
    address public constant REX_TOKEN =
        0x263026E7e53DBFDce5ae55Ade22493f828922965; // REX Protocol Token
    INonfungiblePositionManager public nonfungiblePositionManager; // Uniswap V3 NFT Manager
    ISwapRouter02 public router; // UniswapV3 Router
    address public selfCompounder; // Revert Finance Self-Compounder
    uint256[] public uniswapNFTs;
    bytes32[] public compoundTaskIds;

    event NFTDeposited(uint256 tokenId, bytes32 taskId);
    event Compounded(uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1);
    event SwappedForGelatoGas(address token, uint256 amount);

    constructor(
        address _selfCompounder,
        address _automate,
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISwapRouter02 _uniswapRouter
    ) AutomateTaskCreator(_automate, address(this))
    {
        selfCompounder = _selfCompounder;
        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
        router = _uniswapRouter;
    }

    function onERC721Received(
        address /*to*/,
        address /*from*/,
        uint256 tokenId,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        PositionState memory state;
        bytes32 taskId;

        // Require that the sender is the Uniswap V3 NFT contract
        require(
            msg.sender == address(nonfungiblePositionManager),
            "!univ3 pos"
        );

        (, , state.token0, state.token1, state.fee, , , , , , , ) = nonfungiblePositionManager.positions(tokenId);

        // Require the position has a fee equal to the UNISWAP_FEE
        require(state.fee == UNISWAP_FEE, "!univ3 fee");

        // Approve Uniswap Router to spend token0 and token1
        // TODO: Safe approve?
        IERC20(state.token0).approve(address(router), type(uint256).max);
        IERC20(state.token1).approve(address(router), type(uint256).max);

        // Record the NFT was received
        uniswapNFTs.push(tokenId);

        // Create the Gelato Automate task for collectFees
        taskId = _createCompoundTask(tokenId);
        compoundTaskIds.push(taskId);

        // Emit an event for the new NFT deposited
        emit NFTDeposited(tokenId, taskId);

        return this.onERC721Received.selector;
    }

    function compound(uint256 tokenId) external {
        PositionState memory state;

        // Collect 1 wei worth of tokens so that `tokensOwed0` and `tokensOwed1` are updated
        nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: 1,
                amount1Max: 1
            })
        );

        // Get the Uniswap V3 NFT
        (, , state.token0, state.token1, , , , , , , state.tokensOwed0, state.tokensOwed1) = nonfungiblePositionManager.positions(tokenId);


        // Check how much fees are owed on this position and compute the fees for Gelato
        state.tokensForGelato0 = (state.tokensOwed0 * GELATO_FEE_SHARE) / 100;
        state.tokensForGelato1 = (state.tokensOwed1 * GELATO_FEE_SHARE) / 100;

        // Collect the fees on this position to pay for gas
        nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: uint128(state.tokensForGelato0),
                amount1Max: uint128(state.tokensForGelato1)
            })
        );

        // There will be some token0 and token1 left over in the contract from last compounding
        // Tokens for Gelato is updated to use the full available balance of token0 and token1
        state.tokensForGelato0 = IERC20(state.token0).balanceOf(address(this));
        state.tokensForGelato1 = IERC20(state.token1).balanceOf(address(this));

        // Swap the balances to get native gas tokens
        _swapForGas(state);

        // Tranfers the NFT to SelfCompounder to perform the autocompound
        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            selfCompounder,
            tokenId
        );
        (, , state.token0, state.token1, , , , , , , state.tokensOwed0, state.tokensOwed1) = nonfungiblePositionManager.positions(tokenId);
        emit Compounded(tokenId, state.token0, state.token1, state.tokensOwed0, state.tokensOwed1);
        // SelfCompounder returns the Uniswap V3 NFT to this contract after compounding
        // SelfCompounder also returns some left over token0 and token1
        // These leftovers are used the next time Gelato calls this function

        // Pay Gelato for gas used
        _payGelato();
    }

    function _swapForGas(PositionState memory state) internal {
        bytes memory path; // The path for the Uniswap

        if (state.token0 != REX_TOKEN) {
            // Swap token0 for REX_TOKEN
            path = abi.encodePacked(
                address(state.token0),
                UNISWAP_FEE,
                address(REX_TOKEN)
            );
            _swap(path, state.tokensForGelato0);
        } else {
            // Swap token1 for REX_TOKEN
            path = abi.encodePacked(
                address(state.token1),
                UNISWAP_FEE,
                address(REX_TOKEN)
            );
            _swap(path, state.tokensForGelato1);
        }

        // at this point, we have all REX_TOKEN, swap it for WMATIC
        path = abi.encodePacked(
            address(REX_TOKEN),
            UNISWAP_FEE,
            address(WRAPPED_GAS_TOKEN)
        );
        _swap(path, IERC20(REX_TOKEN).balanceOf(address(this)));

        emit SwappedForGelatoGas(state.token0, state.tokensForGelato0);
        emit SwappedForGelatoGas(state.token1, state.tokensForGelato1);
    }

    function _swap(bytes memory path, uint256 amount) internal {
        // Swap the token for the next token in the path
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: amount,
                // Swapping for gas, transactions too small to front run
                // Transaction will also fail in `_payGelato` if not enough MATIC is received
                amountOutMinimum: 0
            });
        router.exactInput(params);
    }

    function _payGelato() internal {
        // Withdraw all available matic
        IWMATIC(WRAPPED_GAS_TOKEN).withdraw(
            IWMATIC(WRAPPED_GAS_TOKEN).balanceOf(address(this))
        );

        // Get the fee details from Gelato Automate
        (uint256 fee, address feeToken) = _getFeeDetails();

        // If there is a Gelato Fee to pay
        if (fee > 0) {
            _transfer(fee, feeToken);
            // Otherwise there is no fee to pay, just return
        } else {
            return;
        }

        // Any left over matic will get used to trigger the next autocompound
    }

    function _createCompoundTask(
        uint256 tokenId
    ) internal returns (bytes32 taskId) {
        // Create a timed interval task with Gelato Network
        bytes memory execData = abi.encodeCall(this.compound, (tokenId));
        ModuleData memory moduleData = ModuleData({
            modules: new Module[](1),
            args: new bytes[](1)
        });
        moduleData.modules[0] = Module.TIME;
        moduleData.args[0] = _timeModuleArg(block.timestamp, INTERVAL);
        taskId = _createTask(address(this), execData, moduleData, ETH);
    }

    receive() external payable {}

}
