// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LoanRepaymentTracker is Ownable {
    error InvalidBorrowerAddress();
    error PrincipalMustGreaterThanZero();
    error InstallmentMustGreaterThanZero();
    error PrincipalTransferFailed();
    error LoanIsNotActive();
    error PaymentAmountMustGreaterThanZero();
    error PaymentTransferFailed();
    error PaymentNotOverdueyet();
    error LateFeeAlreadyApplied();
    error GracePeriodStillActive();
    error WithdrawalFailed();

    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 principalAmount
    );

    event LoanFullyPaid(uint256 indexed loanId);

    event RePaymentMade(
        uint256 indexed loanid,
        address indexed borrower,
        uint256 amount
    );

    event LateFeeApplied(uint256 indexed loanId, uint256 appliedLateFees);

    event LoanDefaulted(uint256 indexed loanId);

    enum LoanStatus {
        Active,
        Paid,
        Defaulted
    }

    struct Loan {
        address borrower;
        uint256 principal;
        uint256 totalRemaining;
        uint256 monthlyInstallment;
        uint256 lastPaymentTimestamp;
        uint256 nextDueTimestamp;
        uint256 lateFeeAmount;
        uint256 gracePeriod;
        LoanStatus status;
        bool lateFeeAppliedForCurrentMonth;
    }

    IERC20 public immutable LOAN_TOKEN;
    uint256 public constant MONTH_DURATION = 30 days;

    mapping(uint256 => Loan) public loans;
    uint256 public loanCount;

    constructor(address _loanToken) Ownable(msg.sender) {
        require(_loanToken != address(0), "Invalid Token Address");
        LOAN_TOKEN = IERC20(_loanToken);
    }

   
}
