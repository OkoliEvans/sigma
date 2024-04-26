// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @title An on-chain voting system that only allows verified ctizens to vote, mitigating fraud and double voting.
/// @author Okoli Evans, Ominisan Patrick, Olorunfemi Babalola Samuel
/// @notice For open and trusted voting system that allows only verified accounts to access vote function. Vote results are returned in real time.
/// @dev Restricts access to 'Controller', 'Agents' and actual voters. Returns vote counts autonomously to the frontend via interval calls

import "./voting.sol";
import "../interface/IVoting.sol";

contract votingFactory {
    event CreateElection(address votingAddr, address overseer);

    struct Contest {
        uint256 _voteID;
        bool _idRegd;
        address _overseer;
        address _election;
        string _contest;
    }

    mapping(uint256 => Contest) public contestToID;
    mapping(address => uint256) electionToID;
    address[] public elections;
    address public Moderator;

    modifier onlyModerator() {
        require(msg.sender == Moderator);
        _;
    }

    constructor() {
        Moderator = msg.sender;
    }

    /// @param name_ Name for ERC721 token
    /// @param symbol_ Symbol for ERC721 token
    /// @param childElection stands for child Election Address
    function createElection(
        uint256 voteId,
        string calldata name_,
        string calldata symbol_,
        string calldata tokenUri,
        string calldata _contest,
        uint start
    ) external returns (address childElection) {
        Contest storage contest = contestToID[voteId];
        if (voteId == contest._voteID) revert("createElection: ID taken");
        if(block.timestamp > start) revert("createElection: Invalid time");
        bytes32 nullHash = keccak256(abi.encode(""));
        bytes32 uriHash = keccak256(abi.encode(tokenUri));
        if (uriHash == nullHash) revert("createElection: Empty uri");

        Voting voting = new Voting(
            name_,
            symbol_,
            tokenUri,
            _contest,
            msg.sender,
            Moderator,
            start
        );

        address votingAddr = address(voting);

        contest._voteID = voteId;
        contest._idRegd = true;
        contest._overseer = msg.sender;
        contest._election = votingAddr;
        contest._contest = _contest;
        
        electionToID[votingAddr] = voteId;
        elections.push(votingAddr);

        childElection = votingAddr;
        emit CreateElection(votingAddr, msg.sender);
    }

    ///@notice Function returns the ID of an election when the address is supplied
    function retElectionID(
        address electionAddr
    ) external view returns (uint256 Id) {
        Id = electionToID[electionAddr];
    }

    ///@notice Function returns all election instances created
    function retElections() external view returns (address[] memory) {
        return elections;
    }

    ///@notice Function reassigns Moderator role to new address
    function replcModerator(address newMod) external onlyModerator {
        if (newMod == address(0)) revert("replaceModerator: Address_0");
        Moderator = newMod;
    }

    ///@notice Function returns the total number, n, of election instances created
    function nElections() external view returns (uint256 totalElections) {
        totalElections = elections.length;
    }

    function wthr(address to, uint amount) external onlyModerator {
        if (to == address(0)) revert("wthr: Address_0");
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert("wthr: Ether withdraw fail..");
    }

    function rc(uint voteId) external view returns(Contest memory) {
        Contest storage contest = contestToID[voteId];
        return contest;
    }

    receive() external payable {}
}
