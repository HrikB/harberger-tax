// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC4907} from "./IERC4907.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract Harberger is IERC721Metadata, Context {
    using Address for address;
    using Counters for Counters.Counter;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Token in which the tax is paid
    ERC20 private _token;

    Counters.Counter private _tokenIdTracker;

    uint256 private _firstTimePeriod;
    uint256 internal constant _period = 1 days * 365;

    uint256 taxNumerator;
    uint256 taxDenominator;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to time period to current owner's valuation of the token
    mapping(uint256 => mapping(uint256 => uint256)) private _valuations;

    // Mapping from token ID to time period to whether current owner paid taxes
    mapping(uint256 => mapping(uint256 => bool)) private _hasPaid;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    constructor(
        string memory name_,
        string memory symbol_,
        ERC20 token_,
        uint256 taxNumerator_,
        uint256 taxDenominator_
    ) {
        _name = name_;
        _symbol = symbol_;
        _token = token_;
        _firstTimePeriod = block.timestamp;
        taxNumerator = taxNumerator_;
        taxDenominator = taxDenominator_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {}

    function mint(uint256 price) external {
        _mint(msg.sender, _tokenIdTracker.current(), price);
        _tokenIdTracker.increment();
    }

    function balanceOf(address) external pure returns (uint256) {
        revert("Not Implemented");
    }

    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner or approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        require(_exists(tokenId));

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override
    {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    function supportsInterface(bytes4 interfaceId)
        external
        view
        returns (bool)
    {}

    function getCurrentPeriod() public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        return timestamp - ((timestamp - _firstTimePeriod) % _period);
    }

    function payTaxes(uint256 tokenId, uint256 valuation) external {
        uint256 currentPeriod = getCurrentPeriod();
        require(
            _hasPaid[tokenId][currentPeriod] == false,
            "Harberger: You have already paid taxes for this period"
        );

        // Change the valuation of this tokenId for the rest of the current
        // period as well as the next period
        _valuations[tokenId][currentPeriod] = valuation;
        _valuations[tokenId][currentPeriod + _period] = valuation;
        _hasPaid[tokenId][currentPeriod] = true;

        uint256 tax = (valuation * taxNumerator) / taxDenominator;
        _token.transferFrom(msg.sender, address(this), tax);
    }

    function buy(uint256 tokenId, uint256 valuation) external {
        uint256 currentPeriod = getCurrentPeriod();
        require(
            valuation >= _valuations[tokenId][currentPeriod],
            "Harberger: Valuation too low"
        );
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "Harberger: Token does not exist");

        _valuations[tokenId][currentPeriod] = valuation;
        _hasPaid[tokenId][currentPeriod] = false;

        _token.transferFrom(msg.sender, owner, valuation);
        _transfer(owner, msg.sender, tokenId);
    }

    /**
     * @dev Minting of a new token.
     * @param to The address that will own the minted token
     * @param tokenId The token id to mint
     * @param price The initial price that the buyer is willing to pay for this token
     */
    function _mint(
        address to,
        uint256 tokenId,
        uint256 price
    ) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        // unchecked {
        //     // Will not overflow unless all 2**256 token ids are minted to the same owner.
        //     // Given that tokens are minted one by one, it is impossible in practice that
        //     // this ever happens. Might change if we allow batch minting.
        //     // The ERC fails to describe this case.
        //     _balances[to] += 1;
        // }

        uint256 currentPeriod = getCurrentPeriod();

        _owners[tokenId] = to;
        _valuations[currentPeriod][tokenId] = price;

        _hasPaid[currentPeriod - _period][tokenId] = true;

        _token.transferFrom(to, address(this), price);

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IERC721Receiver(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            isApprovedForAll(owner, spender) ||
            getApproved(tokenId) == spender);
    }

    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        address owner = _owners[tokenId];
        // If previous period's taxes were not paid, return address(0)
        if (!_hasPaid[getCurrentPeriod() - _period][tokenId]) return address(0);
        return owner;
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(
            ownerOf(tokenId) == from,
            "ERC721: transfer from incorrect owner"
        );
        require(to != address(0), "ERC721: transfer to the zero address");

        // Check that tokenId was not transferred by `_beforeTokenTransfer` hook
        require(
            ownerOf(tokenId) == from,
            "ERC721: transfer from incorrect owner"
        );

        // Clear approvals from the previous owner
        delete _tokenApprovals[tokenId];

        // unchecked {
        //     // `_balances[from]` cannot overflow for the same reason as described in `_burn`:
        //     // `from`'s balance is the number of token held, which is at least one before the current
        //     // transfer.
        //     // `_balances[to]` could overflow in the conditions described in `_mint`. That would require
        //     // all 2**256 token ids to be minted, which in practice is impossible.
        //     _balances[from] -= 1;
        //     _balances[to] += 1;
        // }
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }
}
