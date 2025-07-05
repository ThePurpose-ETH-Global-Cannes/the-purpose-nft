// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WinnerTakeAllPool5Level {

    IERC20 public immutable token;
    address public owner;

    uint256 public gameEndTime;
    uint256 internal totalPool;
    address internal winner;
    uint256 public stakeSize = 10; // Need to clarify later


    modifier onlyOwner() {
        require(msg.sender == owner, "Not an owner.");
        _;
    }


    mapping(address => uint256) public deposits;
    address[] public participants;

    event GameStarted(uint256 endTime);
    event Deposited(address indexed user, uint256 amount, string domain);
    event WinnerSelected(address indexed winner);
    event TotalPrizeClaimed(address indexed winner, uint256 amount);
    event SingleShareOfPrizeClaimed(address indexed shareReceiver, uint256 amount);

    bool eventGameStartedEmittedOnce = false;

    error GameAlreadyStarted();

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
        owner = msg.sender;
    }


    function _getRandomNumber(uint256 _participantsCount) private view returns (uint256){}

    function _makeConnectionRequest(address _toConnectWith) private {
        connectionsRequests[_toConnectWith].push(msg.sender);
    }


    function startGame(uint256 _duration) external onlyOwner {
        require(eventGameStartedEmittedOnce == false, "The game has been started.");

        gameEndTime = block.timestamp + _duration;
        emit GameStarted(gameEndTime);
        eventGameStartedEmittedOnce = true;
    }

    function deposit(string memory _domain) external {
        require(bytes(_domain).length != 0, "Domain can not be empty.");
        require(block.timestamp <= gameEndTime, "The game has ended.");
        require(gameEndTime > block.timestamp, "The game is not started or already ended.");
        require(deposits[msg.sender] <= 10, "Can not stake more than once.");  // Need checking later

        if (deposits[msg.sender] == 0) {
            participants.push(msg.sender);
        }

        deposits[msg.sender] += stakeSize;
        totalPool += stakeSize;
        token.transferFrom(msg.sender, address(this), stakeSize);

        emit Deposited(msg.sender, stakeSize, _domain);
    }

    function selectWinner() external {
        require (block.timestamp > gameEndTime, "The game has not ended yet.");
        require (winner != address(0), "Invalid address.");
        require (participants.length != 0, "No participants to choose a winner from.");

        uint256 winningTicket = _getRandomNumber(participants.length);
        uint256 currentTicket = 0;

        for (uint256 i = 0; i < participants.length; i++) {
            address currentUser = participants[i];
            currentTicket += deposits[currentUser];
            if (winningTicket < currentTicket) {
                winner = currentUser;
                emit WinnerSelected(winner);
                return;
            }
        }
    }

    function claimPrize() external {
        require(msg.sender == winner, "Not a winner.");
        require(totalPool != 0, "Prize is already claimed.");

        uint256 connectionsCount = connections[winner].length + 1;
        uint256 prizeAmount = totalPool;
        uint256 prizePerUser = prizeAmount / connectionsCount;
        totalPool = 0; // Prevent re-entrancy


        uint256 distributedToConnections = 0;
        for (uint i = 0; i < connectionsCount; i++) {
            token.transfer(connections[winner][i], prizePerUser);
            distributedToConnections += prizePerUser;

            emit SingleShareOfPrizeClaimed(connections[winner][i], prizePerUser);
        }
        uint256 winnerPrize = prizeAmount - distributedToConnections;
        token.transfer(winner, winnerPrize);

        emit TotalPrizeClaimed(winner, prizeAmount);
        
        // Reset game state for the next round.
        eventGameStartedEmittedOnce = false;
    }



    // Service functions
    
    function _getRandomNumber(uint256 _participantsCount) private view returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, participants.length)));
        return random % _participantsCount;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }

    function isTheGameIsOn() external view returns (bool) {
        return gameEndTime != 0 && block.timestamp < gameEndTime;
    }
}
