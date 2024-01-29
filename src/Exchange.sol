/**
 * @title Uniswap V1 copy
 * @author Aayush Gupta
 * @notice Some things to remember,
 * Uinswap only allow swapping of ETH <-> Token, not Token0 <-> Token1, remember that
 * LP Tokens minted for user is equal to the amount of ETH
 *
 */

//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error INVALID_TOKEN_ADDRESS();
error INSUFFICIENT_TOKEN_AMOUNT();
error INVALID_AMOUNT();

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

    constructor(address _token) ERC20("uniswap-V1", "UNI-V1") {
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

            uint256 liquidity = address(this).balance;
            // mint LP Tokens
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

    function ethToTokenTransfer(
        uint256 _minTokens,
        address _recipient
    ) public payable {
        ethToToken(_minTokens, _recipient);
    }

    function ethToTokenSwap(uint256 _minTokens) public payable {
        ethToToken(_minTokens, msg.sender);
    }

    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );

        require(ethBought >= _minEth, "insufficient output amount");

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
        require(
            exchangeAddress != address(this) && exchangeAddress != address(0),
            "invalid exchange address"
        );

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

    function ethToToken(uint256 _minTokens, address recipient) private {
        uint256 tokenReserve = getReserve();
        uint256 tokensBought = getAmount(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve
        );

        require(tokensBought >= _minTokens, "insufficient output amount");

        IERC20(tokenAddress).transfer(recipient, tokensBought);
    }

    function getAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) private pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");

        uint256 inputAmountWithFee = inputAmount * 99;
        uint256 numerator = inputAmountWithFee * outputReserve;
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
        require(_ethSold > 0, "ethSold is too small");

        uint256 tokenReserve = getReserve();

        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 _tokenSold) public view returns (uint256) {
        require(_tokenSold > 0, "tokenSold is too small");

        uint256 tokenReserve = getReserve();

        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }
}
