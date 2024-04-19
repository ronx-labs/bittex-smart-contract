// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IERC20 {
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
    function approve(address _spender, uint256 _amount) external returns (bool);
    function transfer(address _recipient, uint256 _amount) external returns (bool);
}


contract Bittex {
    address private _owner;

    struct Swap {
        address                     inputToken;
        address                     outputToken;
        address                     topBidder1;
        address                     topBidder2;
        address                     topBidder3;
        address                     winner;
        uint256                     inputTokenAmount;
        uint256                     timestamp;
        bytes32                     swapId;
        address[]                   bidders;
        mapping(address => bool)    hasWithdrawn;
        mapping(address => uint256) bids;
    }

    mapping(bytes32 => Swap) public swaps;
    mapping(bytes32 => address) private swapCreators;
    mapping(address => bool) public tokenWhitelist;

    uint constant expiryTime = 300;
    bool internal locked;

    event SwapCreated(bytes32 swapId);

    constructor() {
        _owner = msg.sender;
    }

    modifier noReentrant() {
        require(!locked, "No re-entrancy allowed");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyOwner {
        require(msg.sender == _owner, "Only the contract owner can call this function");
        _;
    }

    modifier onlySwapCreator(bytes32 _swapId) {
        require(msg.sender == swapCreators[_swapId], "Only the swap creator can perform this action");
        _;
    }

    modifier onlyWhitelisted(address token) {
        require(tokenWhitelist[token], "Token not whitelisted");
        _;
    }

    function whitelistToken(address _token, bool _status) public onlyOwner {
        tokenWhitelist[_token] = _status;
    }

    function updateTopBidders(bytes32 _swapId, address _bidder, uint256 _bidAmount) private {
        // Update the top 3 bidders
        Swap storage swap = swaps[_swapId];
        if (_bidAmount > swap.bids[swap.topBidder1]) {
            swap.topBidder3 = swap.topBidder2;
            swap.topBidder2 = swap.topBidder1;
            swap.topBidder1 = _bidder;
        } else if (_bidAmount > swap.bids[swap.topBidder2]) {
            swap.topBidder3 = swap.topBidder2;
            swap.topBidder2 = _bidder;
        } else if (_bidAmount > swap.bids[swap.topBidder3]) {
            swap.topBidder3 = _bidder;
        }
    }

    function chooseRandomBidder(bytes32 _swapId) private view returns (address) {
        // Choose a random bidder from the top 3 bidders
        Swap storage swap = swaps[_swapId];
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)));
        if (swap.topBidder1 == address(0))
            return address(0);
        if (swap.topBidder2 == address(0))
            return swap.topBidder1;
        if (swap.topBidder3 == address(0))
            return randomNumber % 2 == 0 ? swap.topBidder1 : swap.topBidder2;
        if (randomNumber % 3 == 0)
            return swap.topBidder1;
        if (randomNumber % 3 == 1)
            return swap.topBidder2;
        return swap.topBidder3;
    }

    function getBidInfo(bytes32 _swapId, address _bidder) public view returns (uint256) {
        // Get bid information
        return swaps[_swapId].bids[_bidder];
    }

    function getWinner(bytes32 _swapId) public view returns (address) {
        // Get the winner of the swap
        return swaps[_swapId].winner;
    }

    function isFinalized(bytes32 _swapId) public view returns (bool) {
        // Check if the swap has been finalized
        return swaps[_swapId].winner != address(0);
    }

    function isExpired(bytes32 _swapId) public view returns (bool) {
        // Check if the swap has expired
        return block.timestamp > swaps[_swapId].timestamp + expiryTime;
    }

    function createSwap(address _inputToken, address _outputToken, uint256 _inputTokenAmount)
        public 
        onlyWhitelisted(_inputToken)
        onlyWhitelisted(_outputToken)
        returns (bytes32 swapId)
    {
        require(_inputToken != _outputToken, "Input and output tokens cannot be the same");
        require(_inputTokenAmount > 0, "Input token amount must be greater than 0");

        // Generate swapId by hashing creator, inputToken, outputToken, inputTokenAmount and timestamp
        swapId = keccak256(abi.encodePacked(msg.sender, _inputToken, _outputToken, _inputTokenAmount, block.timestamp));

        // Create a new Swap instance in storage
        Swap storage newSwap = swaps[swapId];
        newSwap.swapId = swapId;
        newSwap.inputToken = _inputToken;
        newSwap.outputToken = _outputToken;
        newSwap.inputTokenAmount = _inputTokenAmount;
        newSwap.timestamp = block.timestamp;

        // Store the swap creator
        swapCreators[swapId] = msg.sender;

        // Emit the SwapCreated event
        emit SwapCreated(swapId);

        return swapId;
    }

    function finalizeSwap(bytes32 _swapId) public onlySwapCreator(_swapId) noReentrant {
        Swap storage swap = swaps[_swapId];

        // Check if the swap has already been finalized
        require(swap.winner == address(0), "The swap has already been finalized");

        // Check if the swap has expired
        require(block.timestamp < swap.timestamp + expiryTime, "The swap has already expired");

        // Get input and output token addresses
        address _inputToken = swap.inputToken;
        address _outputToken = swap.outputToken;

        // Choose a random bidder from the top 3 bidders
        address bidder = chooseRandomBidder(_swapId);
        require(bidder != address(0), "No bidder found");

        // Transfer input token from the swap creator to the bidder
        require(IERC20(_inputToken).transferFrom(msg.sender, bidder, swap.inputTokenAmount), "Transfer failed");

        // Send output token to the swap creator
        require(IERC20(_outputToken).transfer(msg.sender, swap.bids[bidder]), "Transfer failed");

        // Set the winner as the chosen bidder
        swap.winner = bidder;
    }

    function registerBid(bytes32 _swapId, address _bidder, uint256 _bidAmount) private {
        // Register bid information
        Swap storage swap = swaps[_swapId];
        swap.bidders.push(_bidder);
        swap.bids[_bidder] = _bidAmount;
    }

    function makeBid(bytes32 _swapId, uint256 _amount) public noReentrant {
        require(_amount > 0, "Bid amount must be greater than 0");
        Swap storage swap = swaps[_swapId];

        // Ensure that the swap has not expired
        require(block.timestamp < swap.timestamp + expiryTime, "Cannot bid on expired swap");

        // Ensure that a bidder has not already made a bid
        require(swap.bids[msg.sender] == 0, "Each bidder can only make one bid");

        // Ensure that the swap creator is not bidding on his own swap
        require(msg.sender != swapCreators[_swapId], "Swap creator cannot bid on his own swap");

        // Transfer output token from the bidder to this contract
        address _outputToken = swaps[_swapId].outputToken;
        require(_outputToken != address(0), "Swap ID not found");
        require(IERC20(_outputToken).transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        // Update the top 3 bidders
        updateTopBidders(_swapId, msg.sender, _amount);

        // Register bid information
        registerBid(_swapId, msg.sender, _amount);
    }

    function withdrawBid(bytes32 _swapId) public noReentrant {
        Swap storage swap = swaps[_swapId];

        // Check if the swap has been finalized or expired
        require(swap.winner != address(0) || block.timestamp > swap.timestamp + expiryTime, "The swap has not been finalized or expired yet");

        // Get bid information from swaps stored in the storage
        uint256 bidAmount = swap.bids[msg.sender];
        require(bidAmount > 0, "No bid found for the given address in this swap. Cannot withdraw.");

        // Check if the withdrawer is the winner
        require(msg.sender != swap.winner, "Winner cannot withdraw bid");

        // Check if the withdrawer has already made a withdrawal
        require(!swap.hasWithdrawn[msg.sender], "Withdrawer has already made a withdrawal");

        // Send output token to the withdrawer
        address _outputToken = swap.outputToken;
        require(IERC20(_outputToken).transfer(msg.sender, bidAmount), "Transfer failed");

        // Mark the withdrawer as withdrawn
        swap.hasWithdrawn[msg.sender] = true;
    }
}
