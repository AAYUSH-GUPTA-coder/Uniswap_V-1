/**
 * @title Uniswap V1 copy
 * @author Aayush Gupta
 * @notice Some things to remember,
 * Uinswap only allow swapping of ETH <-> Token, not Token0 <-> Token1, remember that
 * LP Tokens minted for user is equal to the amount of ETH
 * @note All the ERC20 functions are for LP tokens
 */

//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error INVALID_TOKEN_ADDRESS();
error INSUFFICIENT_TOKEN_AMOUNT();
error INVALID_AMOUNT();
error INVALID_RESERVE();
error INSUFFICIENT_OUTPUT_AMOUNT();
error ETHSOLD_IS_TOO_SMALL();
error TOKENSOLD_IS_TOO_SMALL();
error INVALID_EXCHANGE_ADDRESS();

interface IExchange {
    function ethToTokenSwap(uint256 _minTokens) external payable;

    function ethToTokenTransfer(
        uint256 _minTokens,
        address _recipient
    ) external payable;
}

interface IFactory {
    function getExchange(address _tokenAddress) external returns (address);
}

contract Exchange is ERC20 {
    address public tokenAddress;
    address public factoryAddress;

    constructor(address _token) ERC20("Liquidity-Token", "LT") {
        if (_token == address(0)) revert INVALID_TOKEN_ADDRESS();

        // set token
        tokenAddress = _token;
        factoryAddress = msg.sender;
    }

    /**
     * @notice function to add liquidity to the Pool
     * @param _tokenAmount: The amount user wants to deposit
     * @dev user first need to approve this contract to use ERC20 token
     * @dev User need to provide both ETH and tokens for liquidity in the same ratio
     */
    function addLiquidity(
        uint256 _tokenAmount
    ) public payable returns (uint256) {
        if (getReserve() == 0) {
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), _tokenAmount);

            // mint LP Tokens, amount of LP is equal to amount of ETH
            uint256 liquidity = address(this).balance;
            _mint(msg.sender, liquidity);

            return liquidity;
        } else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = getReserve();
            // check to maintain the perfect ratio
            uint256 tokenAmountCalculated = (msg.value * tokenReserve) /
                ethReserve;
            if (_tokenAmount < tokenAmountCalculated)
                revert INSUFFICIENT_TOKEN_AMOUNT();

            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(
                msg.sender,
                address(this),
                tokenAmountCalculated
            );

            uint256 liquidity = (msg.value * totalSupply()) / ethReserve;
            _mint(msg.sender, liquidity);

            return liquidity;
        }
    }

    /**
     * function to remove Liquidity
     */
    function removeLiquidity(
        uint256 _amount
    ) public returns (uint256, uint256) {
        if (_amount == 0) revert INVALID_AMOUNT();

        uint256 ethAmount = (address(this).balance * _amount) / totalSupply();
        uint256 tokenAmountCalculated = (getReserve() * _amount) /
            totalSupply();

        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(ethAmount);
        IERC20(tokenAddress).transfer(msg.sender, tokenAmountCalculated);

        return (ethAmount, tokenAmountCalculated);
    }

    // function to swap tokens and send to another address, eth <-> token
    function ethToTokenTransfer(
        uint256 _minTokens,
        address _recipient
    ) public payable {
        ethToToken(_minTokens, _recipient);
    }

    // function to swap tokens, eth <-> token
    function ethToTokenSwap(uint256 _minTokens) public payable {
        ethToToken(_minTokens, msg.sender);
    }

    // function to swap ETH, token <-> eth
    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );

        if (ethBought < _minEth) revert INSUFFICIENT_OUTPUT_AMOUNT();

        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );
        payable(msg.sender).transfer(ethBought);
    }

    function tokenToTokenSwap(
        uint256 _tokensSold,
        uint256 _minTokensBought,
        address _tokenAddress
    ) public {
        address exchangeAddress = IFactory(factoryAddress).getExchange(
            _tokenAddress
        );
        if (exchangeAddress == address(this) && exchangeAddress == address(0)) {
            revert INVALID_EXCHANGE_ADDRESS();
        }

        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );

        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );

        IExchange(exchangeAddress).ethToTokenTransfer{value: ethBought}(
            _minTokensBought,
            msg.sender
        );
    }

    ////////////////////////////////////
    //          PRIVATE             ///
    ///////////////////////////////////
    // private function to transfer tokens
    function ethToToken(uint256 _minTokens, address recipient) private {
        uint256 tokenReserve = getReserve();
        uint256 tokensBought = getAmount(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve
        );

        if (tokensBought < _minTokens) revert INSUFFICIENT_TOKEN_AMOUNT();

        IERC20(tokenAddress).transfer(recipient, tokensBought);
    }

    /**
     * @notice function to get the output token amount
     * @dev output token amount already deducted the pool / swap fee of 1%
     * @param inputAmount amount to swap
     * @param inputReserve amount of input token in the smart contract
     * @param outputReserve amount of output token in the smart contract
     */
    function getAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) private pure returns (uint256) {
        if (inputReserve == 0 && outputReserve == 0) revert INVALID_RESERVE();

        uint256 inputAmountWithFee = inputAmount * 99;
        uint256 numerator = outputReserve * inputAmountWithFee;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;

        return numerator / denominator;
    }

    ////////////////////////////////////
    //          VIEW                 ///
    ///////////////////////////////////

    // Balance of erc20 token of the contract
    function getReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getTokenAmount(uint256 _ethSold) public view returns (uint256) {
        if (_ethSold == 0) revert ETHSOLD_IS_TOO_SMALL();

        uint256 tokenReserve = getReserve();

        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 _tokenSold) public view returns (uint256) {
        if (_tokenSold == 0) revert TOKENSOLD_IS_TOO_SMALL();

        uint256 tokenReserve = getReserve();

        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }
}
