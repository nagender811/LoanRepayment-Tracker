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

    function createLoan(
        address _borrower,
        uint256 _principal,
        uint256 _monthlyInstallment,
        uint256 _lateFeeAmount,
        uint256 _gracePeriod
    ) external onlyOwner {
        if (_borrower == address(0)) revert InvalidBorrowerAddress();
        if (_principal < 0) revert PrincipalMustGreaterThanZero();
        if (_monthlyInstallment < 0) revert InstallmentMustGreaterThanZero();

        loanCount++;

        loans[loanCount] = Loan({
            borrower: _borrower,
            principal: _principal,
            totalRemaining: _principal,
            monthlyInstallment: _monthlyInstallment,
            lastPaymentTimestamp: block.timestamp,
            nextDueTimestamp: block.timestamp + MONTH_DURATION,
            lateFeeAmount: _lateFeeAmount,
            gracePeriod: _gracePeriod,
            status: LoanStatus.Active,
            lateFeeAppliedForCurrentMonth: false
        });

        bool success = LOAN_TOKEN.transferFrom(
            msg.sender,
            _borrower,
            _principal
        );

        if (!success) revert PrincipalTransferFailed();

        emit LoanCreated(loanCount, _borrower, _principal);
    }

    function makeRepayment(uint256 _loanId, uint256 _amount) external {
        Loan storage loan = loans[_loanId];
        if (loan.status != LoanStatus.Active) revert LoanIsNotActive();
        if (_amount < 0) revert PaymentAmountMustGreaterThanZero();

        uint256 transferAmount = _amount;

        if (_amount >= loan.totalRemaining) {
            transferAmount = loan.totalRemaining;
            loan.totalRemaining = 0;
            loan.status = LoanStatus.Paid;
            emit LoanFullyPaid(_loanId);
        } else {
            loan.totalRemaining -= _amount;
        }

        if (transferAmount >= loan.monthlyInstallment) {
            loan.nextDueTimestamp = block.timestamp + MONTH_DURATION;
            loan.lateFeeAppliedForCurrentMonth = false;
        }

        loan.lastPaymentTimestamp = block.timestamp;

        bool success = LOAN_TOKEN.transferFrom(
            msg.sender,
            address(this),
            transferAmount
        );

        if (!success) revert PaymentTransferFailed();

        emit RePaymentMade(_loanId, loan.borrower, transferAmount);
    }

    function enforceLateFee(uint256 _loanId) external onlyOwner {
        Loan storage loan = loans[_loanId];
        if (loan.status != LoanStatus.Active) revert LoanIsNotActive();
        if (loan.nextDueTimestamp > block.timestamp)
            revert PaymentNotOverdueyet();
        if (loan.lateFeeAppliedForCurrentMonth) revert LateFeeAlreadyApplied();

        loan.totalRemaining += loan.lateFeeAmount;
        loan.lateFeeAppliedForCurrentMonth = true;

        emit LateFeeApplied(_loanId, loan.lateFeeAmount);
    }

    function enforceDefault(uint256 _loanId) external {
        Loan storage loan = loans[_loanId];
        if (loan.status != LoanStatus.Active) revert LoanIsNotActive();
        if (loan.nextDueTimestamp > block.timestamp)
            revert PaymentNotOverdueyet();
        if (block.timestamp < loan.nextDueTimestamp + loan.gracePeriod)
            revert GracePeriodStillActive();

        loan.status = LoanStatus.Defaulted;

        emit LoanDefaulted(_loanId);
    }

    function checkOverdueLoans()
        external
        view
        returns (uint256[] memory overdueLoans, uint256[] memory defaultLoans)
    {
        uint256 overdueCount = 0;
        uint256 defaultCount = 0;

        for (uint256 i; i <= loanCount; i++) {
            if (loans[i].status == LoanStatus.Active) {
                if (
                    block.timestamp >
                    loans[i].nextDueTimestamp + loans[i].gracePeriod
                ) {
                    defaultCount++;
                } else if (
                    block.timestamp > loans[i].nextDueTimestamp &&
                    !loans[i].lateFeeAppliedForCurrentMonth
                ) {
                    overdueCount++;
                }
            }
        }

        overdueLoans = new uint256[](overdueCount);
        defaultLoans = new uint256[](defaultCount);

        uint256 oIdx = 0;
        uint256 dIdx = 0;

        for (uint256 i; i <= loanCount; i++) {
            if (loans[i].status == LoanStatus.Active) {
                if (
                    block.timestamp >
                    loans[i].nextDueTimestamp + loans[i].gracePeriod
                ) {
                    defaultLoans[oIdx] = i;
                    dIdx++;
                } else if (
                    block.timestamp > loans[i].nextDueTimestamp &&
                    !loans[i].lateFeeAppliedForCurrentMonth
                ) {
                    overdueLoans[oIdx] = i;
                    oIdx++;
                }
            }
        }
    }

    function withdrawRecoveredFunds(uint256 _amount) external onlyOwner {
        if (LOAN_TOKEN.transfer(owner(), _amount)) revert WithdrawalFailed();
    }
}
