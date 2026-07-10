// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title TokenToCredits
 * @dev A smart contract to convert ERC20 tokens or Native ETH into Translation Credits.
 * Translation credits allow users to utilize premium translation services.
 */
contract TokenToCredits {
    
    address public owner;
    
    // Credit rate: e.g. 1000 credits per 0.01 ETH or 10 Tokens
    uint256 public ethToCreditRate = 100000; // credits per 1 ETH
    uint256 public tokenToCreditRate = 100;  // credits per 1 Token (assuming 18 decimals)
    
    IERC20 public paymentToken;
    
    // Tracks translation credit balance of each user
    mapping(address => uint256) public userCredits;

    event CreditsPurchased(address indexed user, uint256 amountSpent, uint256 creditsEarned, bool isNativeEth);
    event CreditsConsumed(address indexed user, uint256 amountConsumed);
    event RatesUpdated(uint256 newEthRate, uint256 newTokenRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(address _paymentTokenAddress) {
        owner = msg.sender;
        paymentToken = IERC20(_paymentTokenAddress);
    }

    /**
     * @dev Buy translation credits using native ETH
     */
    function buyCreditsWithEth() external payable {
        require(msg.value > 0, "Must send ETH to purchase credits");
        
        uint256 creditsEarned = (msg.value * ethToCreditRate) / 1 ether;
        require(creditsEarned > 0, "Amount too small to earn credits");
        
        userCredits[msg.sender] += creditsEarned;
        
        emit CreditsPurchased(msg.sender, msg.value, creditsEarned, true);
    }

    /**
     * @dev Buy translation credits using the specified ERC20 token
     * @param _tokenAmount Amount of tokens to deposit (in base units, e.g. 18 decimals)
     */
    function buyCreditsWithToken(uint256 _tokenAmount) external {
        require(_tokenAmount > 0, "Must deposit tokens to purchase credits");
        
        // Transfer tokens from user to this contract
        bool success = paymentToken.transferFrom(msg.sender, address(this), _tokenAmount);
        require(success, "Token transfer failed");

        uint256 creditsEarned = (_tokenAmount * tokenToCreditRate) / 1 ether; // Assuming token has 18 decimals
        require(creditsEarned > 0, "Amount too small to earn credits");

        userCredits[msg.sender] += creditsEarned;

        emit CreditsPurchased(msg.sender, _tokenAmount, creditsEarned, false);
    }

    /**
     * @dev Consumes credits (called by BHARAT KI AWAAZ app backend/node to register translation usage)
     * @param _user Address of the user consuming credits
     * @param _amount Number of credits to consume
     */
    function consumeCredits(address _user, uint256 _amount) external onlyOwner {
        require(userCredits[_user] >= _amount, "Insufficient credit balance");
        userCredits[_user] -= _amount;
        
        emit CreditsConsumed(_user, _amount);
    }

    /**
     * @dev Updates conversion rates
     */
    function updateRates(uint256 _newEthRate, uint256 _newTokenRate) external onlyOwner {
        ethToCreditRate = _newEthRate;
        tokenToCreditRate = _newTokenRate;
        
        emit RatesUpdated(_newEthRate, _newTokenRate);
    }

    /**
     * @dev Withdraw native ETH accumulated in contract
     */
    function withdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance to withdraw");
        payable(owner).transfer(balance);
    }

    /**
     * @dev Withdraw ERC20 tokens accumulated in contract
     */
    function withdrawTokens(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No token balance to withdraw");
        
        // Re-use transferFrom interface for withdrawal using transfer equivalent
        // Normally ERC20 interface has transfer, we transfer standard balance to owner
        // using custom signature or contract interface.
        (bool success, ) = _tokenAddress.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, balance)
        );
        require(success, "Token withdrawal failed");
    }
}
