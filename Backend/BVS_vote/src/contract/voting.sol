// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @title An on-chain voting system that only allows verified ctizens to vote, mitigating fraud and double voting.
/// @author Okoli Evans, Ominisan Patrick, Olorunfemi Babalola Samuel
/// @notice For open and trusted voting system that allows only verified accounts to access vote function. Vote results are returned in real time.
/// @dev Restricts access to 'Controller', 'Agents' and actual voters. Returns vote counts autonomously to the frontend via interval calls

import "../../lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract Voting is ERC721, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenId;

    event NewCandidate(address addr, string position);
    event Verified(address _voter, string vn);
    event Voted(address voter, address candidate);

    struct Voter {
        bytes32 _hashVn;
        address _address;
        bool _isVerified;
        bool _voted;
    }

    struct Candidate {
        uint256 _age;
        uint256 _votes;
        address _address;
        string _fullName;
        string _post;
        string _desc;
        bool _isEligible;
    }

    struct Election {
        uint256 startT;
        uint256 endT;
        string contest;
        string tokenURI;
        string baseUri;
        bool started;
    }
    // initialize structs
    Election public election;

    // state variables
    address public GModerator;
    address public overseer;
    address public winner;
    uint256 public totalVotes;
    uint256 _winningVote;

    mapping(address => Candidate) public candidate;
    mapping(address => Voter) public voters;
    bytes32[] verifications;
    Candidate[] public candidates;

    constructor(
        string memory name,
        string memory symbol,
        string memory uri,
        string memory contest,
        address _overseer,
        address moderator,
        uint start
    ) ERC721(name, symbol) {
        GModerator = moderator;
        overseer = _overseer;

        election.startT = start;
        election.contest = contest;
        election.tokenURI = uri;
        election.baseUri = "https://ipfs.io/ipfs/";
    }

    modifier onlyAdmin() {
        require(msg.sender == overseer);
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///////////////// CORE FUNCTIONS  //////////////////////////////
    ////////////////////////////////////////////////////////////////

    /// @param post is the position ot title that is being contested
    /// @param desc is the brief description or introduction of the candidate
    function addCandidate(
        uint256 age,
        address addr,
        string calldata fullName,
        string calldata post,
        string calldata desc
    ) external onlyAdmin {
        if (addr == address(0)) revert("addCandidate: Address_0");
        if (candidate[addr]._address == addr)
            revert("addCandidate: Already added");
        if (age == 0) revert("addCandidate: Invalid age");
        bytes32 nullHash = keccak256(abi.encode(""));
        bytes32 nameHash = keccak256(abi.encode(fullName));
        bytes32 descHsh = keccak256(abi.encode(desc));
        if (nameHash == nullHash || descHsh == nullHash)
            revert("addCandidate: Invalid name or desc");

        candidate[addr]._age = age;
        candidate[addr]._address = addr;
        candidate[addr]._fullName = fullName;
        candidate[addr]._post = post;
        candidate[addr]._desc = desc;
        candidate[addr]._isEligible = true;

        candidates.push(
            Candidate({
                _age: age,
                _votes: 0,
                _address: addr,
                _fullName: fullName,
                _post: post,
                _desc: desc,
                _isEligible: true
            })
        );

        emit NewCandidate(addr, post);
    }

    function rmCandidate(
        address addr
    ) external onlyAdmin returns (Candidate[] memory) {
        if (!candidate[addr]._isEligible)
            revert("rmCandidate: Candidate already disqualified");

        if (addr == candidate[addr]._address) {
            // delete struct instance of candidate
            delete candidate[addr];

            // update Candidate array
            uint256 rmIndex = _retIndexOfCandidate(addr);
            if (rmIndex == candidates.length) {
                revert("rmCandidate: Candidate not found");
            }
            candidates[rmIndex] = candidates[candidates.length - 1];
            candidates.pop();
        }

        return candidates;
    }

    function verify(string calldata vn) external returns (bool success) {
        Voter storage _voter = voters[msg.sender];
        if (_voter._isVerified) revert("verify: Already verified");
        bytes32 vnHash = keccak256(abi.encode(vn));

        for (uint256 i = 0; i < verifications.length; i++) {
            if (verifications[i] == vnHash) {
                revert("verify: VN already in database");
            }
        }

        verifications.push(vnHash);
        _voter._hashVn = vnHash;
        _voter._address = msg.sender;
        _voter._isVerified = true;

        emit Verified(msg.sender, vn);
        success = true;
    }


    ///@notice Returns details of a particular voter
    function retVoter(address addrVoter) external view returns (Voter memory) {
        return voters[addrVoter];
    }

    function startVote(uint end) external onlyAdmin {
        if (end < election.startT) revert("startVote: Invalid time");
        if (candidates.length <= 0)
            revert("startVote: No registered candidates");
        if (election.started) revert("start: Voting already in session");
        if (block.timestamp < election.startT) revert("start: not startTime");

        election.endT = end;
        election.started = true;
    }

    function endVote() external onlyAdmin {
        if (!election.started) revert("end: Voting not in session");
        if (block.timestamp < election.endT) revert("end: not endTime");

        election.started = false;
    }

    function vote(address addrCandidate) external {
        address voter_ = msg.sender;
        string memory uri_ = election.tokenURI;
        uint256 tokenId = _tokenId.current();
        _tokenId.increment();

        if (!election.started) revert("vote: Voting not started");
        if (!voters[voter_]._isVerified) revert("vote: Not verified");
        if (voters[voter_]._voted) revert("vote: Voted");
        if (!candidate[addrCandidate]._isEligible)
            revert("vote: Candidate disqualified");

        if (addrCandidate == candidate[addrCandidate]._address) {
            _vote(addrCandidate);
            _safeMint2(msg.sender, tokenId, uri_);
        }
    }

    function displayElection() external view returns (Election memory) {
        return election;
    }

    function winnerName() external view returns (address, string memory) {
        return (winner, candidate[winner]._fullName);
    }

    function gtTotalVotes() external view returns(uint) {
        return totalVotes;
    }

    function votesPerCandidate(address cand) external view returns(uint) {
        return candidate[cand]._votes;
    }

    ////////////////////////////////////////////////////////////////
    //////////////////// HELPER FUNCTIONS /////////////////////////
    ///////////////////////////////////////////////////////////////

    function _vote(address addrCandidate) internal {
        voters[msg.sender]._voted = true;

        for (uint i = 0; i < candidates.length; i++) {
            if(candidates[i]._address == addrCandidate) {
                candidates[i]._votes += 1;
                candidate[addrCandidate]._votes += 1;
                totalVotes += 1;    
                _setWinner();

                emit Voted(msg.sender, addrCandidate);
                break;
            }
        }
    }

    function _setWinner() internal returns (uint) {
        uint256 winningVote = 0;
        for (uint c = 0; c < candidates.length; c++) {
            if (candidates[c]._votes > winningVote) {
                winningVote = candidates[c]._votes;
                _winningVote = c;

                winner = candidates[_winningVote]._address;
            }
        }
        return _winningVote;
    }

    function _retIndexOfCandidate(
        address addr
    ) internal view returns (uint256) {
        if (addr == candidate[addr]._address) {
            for (uint i; i < candidates.length; i++) {
                if (candidates[i]._address == addr) {
                    return i;
                }
            }
        }
        return candidates.length;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return election.baseUri;
    }

    function _safeMint2(
        address to,
        uint256 tokenId,
        string memory uri
    ) internal {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721URIStorage, ERC721) returns (string memory) {
        _requireMinted(tokenId);

        string memory _tokenURI = election.tokenURI;
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate thevirtual baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        return super.tokenURI(tokenId);
    }

    // soulbound >> non transferable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchsize
    ) internal override {
        require(
            from == address(0) || to == address(0),
            "This token cannot be transferred."
        );
        super._beforeTokenTransfer(from, to, tokenId, batchsize);
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721URIStorage, ERC721) {
        super._burn(tokenId);

        string memory _tokenURI = election.tokenURI;
        if (bytes(_tokenURI).length != 0) {
            delete _tokenURI;
        }
    }
}
