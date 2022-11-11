// SPDX-License-Identifier: WTFPL
pragma solidity ^0.8.17;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {VyperDeployer} from "../../lib/utils/VyperDeployer.sol";

import {IERC165} from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC4494} from "./interfaces/IERC4494.sol";
import {Address} from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import {IERC721Extended} from "../../test/tokens/interfaces/IERC721Extended.sol";

/**
 * Missing unit tests:
 *   - Transfer Event
 *   - Approval Event
 *   - ApprovalForAll Event
 *   - safeTransferFrom
 *   - safeTransferFrom (with data)
 *   - approve
 *   - setApprovalForAll
 *   - getApproved
 *   - isApprovedForAll
 *   - onERC721Received
 *   - tokenURI
 *   - totalSupply
 *   - tokenByIndex
 *   - tokenOfOwnerByIndex
 *   - burn
 *   - safe_mint
 *   - set_minter
 *   - RoleMinterChanged event
 *   - permit
 *   - nonces
 */
contract ERC721Test is Test {
    string private constant _NAME = "MyNFT";
    string private constant _SYMBOL = "WAGMI";
    string private constant _BASE_URI = "https://www.wagmi.xyz/";
    string private constant _NAME_EIP712 = "MyNFT";
    string private constant _VERSION_EIP712 = "1";
    bytes32 private constant _TYPE_HASH =
        keccak256(
            bytes(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            )
        );
    bytes32 private constant _PERMIT_TYPE_HASH =
        keccak256(
            bytes(
                "Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)"
            )
        );

    VyperDeployer private vyperDeployer = new VyperDeployer();

    // solhint-disable-next-line var-name-mixedcase
    IERC721Extended private ERC721Extended;
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private _CACHED_DOMAIN_SEPARATOR;

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    event Approval(
        address indexed owner,
        address indexed approved,
        uint256 indexed tokenId
    );

    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event RoleMinterChanged(address indexed minter, bool status);

    /**
     * @dev An `internal` function that validates a successful transfer call.
     * @param owner The 20-byte owner address.
     * @param tokenId 32-byte identifier of the token.
     * @param receiver The 20-byte receiver address.
     */
    function _transferSuccess(
        address owner,
        uint256 tokenId,
        address receiver
    ) internal {
        assertEq(ERC721Extended.ownerOf(tokenId), receiver);
        assertEq(ERC721Extended.getApproved(tokenId), address(0));
        assertEq(ERC721Extended.balanceOf(owner), 1);
        assertEq(ERC721Extended.balanceOf(receiver), 1);
        assertEq(ERC721Extended.tokenOfOwnerByIndex(receiver, 0), tokenId);
        assertTrue(ERC721Extended.tokenOfOwnerByIndex(owner, 0) != tokenId);
    }

    /**
     * @dev An `internal` function that validates all possible reverts
     * after an invalid transfer call.
     * @param transferFunction The transfer function including the type definitions
     * of the arguments.
     * @param owner The 20-byte owner address.
     * @param tokenId 32-byte identifier of the token.
     * @param receiver The 20-byte receiver address.
     */
    function _transferReverts(
        string memory transferFunction,
        address owner,
        uint256 tokenId,
        address receiver
    ) internal {
        vm.startPrank(vm.addr(5));
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(transferFunction, owner, receiver, tokenId)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(bytes("ERC721: transfer from incorrect owner"));
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(
                transferFunction,
                receiver,
                receiver,
                tokenId
            )
        );
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(bytes("ERC721: invalid token ID"));
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(
                transferFunction,
                receiver,
                receiver,
                tokenId + 2
            )
        );
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(bytes("ERC721: transfer to the zero address"));
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(
                transferFunction,
                owner,
                address(0),
                tokenId
            )
        );
        vm.stopPrank();
    }

    /**
     * @dev An `internal` function that validates all possible successful
     * and reverted transfer calls.
     * @param transferFunction The transfer function including the type definitions
     * of the arguments.
     * @param owner The 20-byte owner address.
     * @param approved The 20-byte approved address.
     * @param operator The 20-byte operator address.
     * @param tokenId 32-byte identifier of the token.
     * @param receiver The 20-byte receiver address.
     */
    function _shouldTransferTokensByUsers(
        string memory transferFunction,
        address owner,
        address approved,
        address operator,
        uint256 tokenId,
        address receiver
    ) internal {
        uint256 snapshot = vm.snapshot();
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, receiver, tokenId);
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(transferFunction, owner, receiver, tokenId)
        );
        _transferSuccess(owner, tokenId, receiver);
        vm.stopPrank();
        vm.revertTo(snapshot);

        snapshot = vm.snapshot();
        vm.startPrank(approved);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, receiver, tokenId);
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(transferFunction, owner, receiver, tokenId)
        );
        _transferSuccess(owner, tokenId, receiver);
        vm.stopPrank();
        vm.revertTo(snapshot);

        snapshot = vm.snapshot();
        vm.startPrank(operator);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, receiver, tokenId);
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(transferFunction, owner, receiver, tokenId)
        );
        _transferSuccess(owner, tokenId, receiver);
        vm.stopPrank();
        vm.revertTo(snapshot);

        snapshot = vm.snapshot();
        vm.startPrank(owner);
        ERC721Extended.approve(address(0), tokenId);
        vm.stopPrank();
        vm.startPrank(operator);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, receiver, tokenId);
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(transferFunction, owner, receiver, tokenId)
        );
        _transferSuccess(owner, tokenId, receiver);
        vm.stopPrank();
        vm.revertTo(snapshot);

        snapshot = vm.snapshot();
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, owner, tokenId);
        Address.functionCall(
            address(ERC721Extended),
            abi.encodeWithSignature(transferFunction, owner, owner, tokenId)
        );
        assertEq(ERC721Extended.ownerOf(tokenId), owner);
        assertEq(ERC721Extended.getApproved(tokenId), address(0));
        assertEq(ERC721Extended.balanceOf(owner), 2);
        assertEq(ERC721Extended.tokenOfOwnerByIndex(owner, 0), tokenId);
        assertTrue(ERC721Extended.tokenOfOwnerByIndex(owner, 1) == tokenId + 1);
        vm.stopPrank();
        vm.revertTo(snapshot);

        /// @dev Validates all possible reverts.
        _transferReverts(transferFunction, owner, tokenId, receiver);
    }

    function setUp() public {
        bytes memory args = abi.encode(
            _NAME,
            _SYMBOL,
            _BASE_URI,
            _NAME_EIP712,
            _VERSION_EIP712
        );
        ERC721Extended = IERC721Extended(
            vyperDeployer.deployContract("src/tokens/", "ERC721", args)
        );
        _CACHED_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                _TYPE_HASH,
                keccak256(bytes(_NAME_EIP712)),
                keccak256(bytes(_VERSION_EIP712)),
                block.chainid,
                address(ERC721Extended)
            )
        );
    }

    function testInitialSetup() public {
        address deployer = address(vyperDeployer);
        assertEq(ERC721Extended.name(), _NAME);
        assertEq(ERC721Extended.symbol(), _SYMBOL);
        assertTrue(ERC721Extended.owner() == deployer);
        assertTrue(ERC721Extended.is_minter(deployer));
    }

    function testSupportsInterfaceSuccess() public {
        assertTrue(ERC721Extended.supportsInterface(type(IERC165).interfaceId));
        assertTrue(ERC721Extended.supportsInterface(type(IERC721).interfaceId));
        assertTrue(
            ERC721Extended.supportsInterface(type(IERC721Metadata).interfaceId)
        );
        assertTrue(
            ERC721Extended.supportsInterface(
                type(IERC721Enumerable).interfaceId
            )
        );
        assertTrue(
            ERC721Extended.supportsInterface(type(IERC4494).interfaceId)
        );
    }

    function testSupportsInterfaceGasCost() public {
        uint256 startGas = gasleft();
        ERC721Extended.supportsInterface(type(IERC165).interfaceId);
        uint256 gasUsed = startGas - gasleft();
        assertTrue(gasUsed < 30_000);
    }

    function testSupportsInterfaceInvalidInterfaceId() public {
        assertTrue(!ERC721Extended.supportsInterface(0x0011bbff));
    }

    function testBalanceOfCase1() public {
        address deployer = address(vyperDeployer);
        address owner = vm.addr(1);
        string memory uri1 = "my_awesome_nft_uri_1";
        string memory uri2 = "my_awesome_nft_uri_2";
        vm.startPrank(deployer);
        ERC721Extended.safe_mint(owner, uri1);
        ERC721Extended.safe_mint(owner, uri2);
        assertEq(ERC721Extended.balanceOf(owner), 2);
        vm.stopPrank();
    }

    function testBalanceOfCase2() public {
        assertEq(ERC721Extended.balanceOf(vm.addr(1)), 0);
    }

    function testBalanceOfZeroAddress() public {
        vm.expectRevert(bytes("ERC721: the zero address is not a valid owner"));
        ERC721Extended.balanceOf(address(0));
    }

    function testOwnerOf() public {
        address deployer = address(vyperDeployer);
        address owner = vm.addr(1);
        string memory uri = "my_awesome_nft_uri";
        vm.startPrank(deployer);
        ERC721Extended.safe_mint(owner, uri);
        assertEq(ERC721Extended.ownerOf(0), owner);
        vm.stopPrank();
    }

    function testOwnerOfInvalidTokenId() public {
        vm.expectRevert(bytes("ERC721: invalid token ID"));
        ERC721Extended.ownerOf(0);
    }

    function testTransferFrom() public {
        address deployer = address(vyperDeployer);
        address owner = vm.addr(1);
        address approved = vm.addr(2);
        address operator = vm.addr(3);
        string memory uri1 = "my_awesome_nft_uri_1";
        string memory uri2 = "my_awesome_nft_uri_2";
        vm.startPrank(deployer);
        ERC721Extended.safe_mint(owner, uri1);
        ERC721Extended.safe_mint(owner, uri2);
        vm.stopPrank();
        vm.startPrank(owner);
        ERC721Extended.approve(approved, 0);
        ERC721Extended.setApprovalForAll(operator, true);
        vm.stopPrank();
        _shouldTransferTokensByUsers(
            "transferFrom(address,address,uint256)",
            owner,
            approved,
            operator,
            0,
            vm.addr(4)
        );
    }

    function testCachedDomainSeparator() public {
        assertEq(ERC721Extended.DOMAIN_SEPARATOR(), _CACHED_DOMAIN_SEPARATOR);
    }

    function testDomainSeparator() public {
        vm.chainId(block.chainid + 1);
        bytes32 digest = keccak256(
            abi.encode(
                _TYPE_HASH,
                keccak256(bytes(_NAME_EIP712)),
                keccak256(bytes(_VERSION_EIP712)),
                block.chainid,
                address(ERC721Extended)
            )
        );
        assertEq(ERC721Extended.DOMAIN_SEPARATOR(), digest);
    }

    function testHasOwner() public {
        assertEq(ERC721Extended.owner(), address(vyperDeployer));
    }

    function testTransferOwnershipSuccess() public {
        address oldOwner = address(vyperDeployer);
        address newOwner = vm.addr(1);
        vm.startPrank(oldOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(oldOwner, newOwner);
        ERC721Extended.transfer_ownership(newOwner);
        assertEq(ERC721Extended.owner(), newOwner);
        vm.stopPrank();
    }

    function testTransferOwnershipNonOwner() public {
        vm.expectRevert(bytes("AccessControl: caller is not the owner"));
        ERC721Extended.transfer_ownership(vm.addr(1));
    }

    function testTransferOwnershipToZeroAddress() public {
        vm.prank(address(vyperDeployer));
        vm.expectRevert(bytes("AccessControl: new owner is the zero address"));
        ERC721Extended.transfer_ownership(address(0));
    }

    function testRenounceOwnershipSuccess() public {
        address oldOwner = address(vyperDeployer);
        address newOwner = address(0);
        vm.startPrank(oldOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(oldOwner, newOwner);
        ERC721Extended.renounce_ownership();
        assertEq(ERC721Extended.owner(), newOwner);
        assertTrue(ERC721Extended.is_minter(oldOwner) == false);
        vm.stopPrank();
    }

    function testRenounceOwnershipNonOwner() public {
        vm.expectRevert(bytes("AccessControl: caller is not the owner"));
        ERC721Extended.renounce_ownership();
    }
}