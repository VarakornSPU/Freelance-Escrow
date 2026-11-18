// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FreelanceEscrowFull {
    enum Status { Created, Funded, Submitted, Completed, Disputed, Refunded }

    struct Project {
        uint projectId;
        string title;
        string description;
        uint amount;
        uint deadline;
        address payable employer;
        address payable freelancer;
        Status status;
        string workHash;
    }

    mapping(uint => Project) public projects;
    uint public projectCounter;

    // กำหนดแอดเดรส Admin ตามที่คุณระบุ
    address public admin = 0x7aebC2A3920D177162f95539FAE8CeCc2D495Ae8;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this");
        _;
    }

    event ProjectCreated(uint projectId, string title, address employer, address freelancer, uint amount);
    event Funded(uint projectId, uint amount);
    event WorkSubmitted(uint projectId, string workHash);
    event Completed(uint projectId, uint amount);
    event Disputed(uint projectId);
    event Refunded(uint projectId, uint amount);
    event DisputeResolved(uint projectId, string winner);

    // 1. สร้างข้อตกลงการจ้างงาน
    function createContract(
        string memory _title, 
        string memory _description, 
        uint _amount, 
        uint _durationDays, 
        address payable _freelancer
    ) public {
        require(_amount > 0, "Amount must be greater than 0");
        
        projectCounter++;
        projects[projectCounter] = Project({
            projectId: projectCounter,
            title: _title,
            description: _description,
            amount: _amount,
            deadline: block.timestamp + (_durationDays * 1 days),
            employer: payable(msg.sender),
            freelancer: _freelancer,
            status: Status.Created,
            workHash: ""
        });

        emit ProjectCreated(projectCounter, _title, msg.sender, _freelancer, _amount);
    }

    // 2. ฝากเงินค่าจ้างเข้า Smart Contract
    function depositPayment(uint _projectId) public payable {
        Project storage proj = projects[_projectId];
        require(msg.sender == proj.employer, "Only employer can deposit");
        require(proj.status == Status.Created, "Invalid status");
        require(msg.value == proj.amount, "Must deposit exact contract amount");

        proj.status = Status.Funded;
        emit Funded(_projectId, msg.value);
    }

    // 3. บันทึกการส่งมอบงาน
    function submitWork(uint _projectId, string memory _workHash) public {
        Project storage proj = projects[_projectId];
        require(msg.sender == proj.freelancer, "Only freelancer can submit");
        require(proj.status == Status.Funded, "Project not funded yet");

        proj.workHash = _workHash;
        proj.status = Status.Submitted;

        emit WorkSubmitted(_projectId, _workHash);
    }

    // 4. อนุมัติและจ่ายเงินปกติ
    function approveAndRelease(uint _projectId) public {
        Project storage proj = projects[_projectId];
        require(msg.sender == proj.employer, "Only employer can approve");
        require(proj.status == Status.Submitted, "Work not submitted yet");

        proj.status = Status.Completed;
        proj.freelancer.transfer(proj.amount);

        emit Completed(_projectId, proj.amount);
    }

    // 5. แจ้งข้อพิพาท (คู่สัญญาใช้งาน)
    function raiseDispute(uint _projectId) public {
        Project storage proj = projects[_projectId];
        require(msg.sender == proj.employer || msg.sender == proj.freelancer, "Not authorized");
        require(proj.status == Status.Funded || proj.status == Status.Submitted, "Cannot dispute");

        proj.status = Status.Disputed;
        emit Disputed(_projectId);
    }

    // 6. ฟังก์ชันตัดสินข้อพิพาทโดย Admin (แอดมินเลือกได้ว่าจะให้ใครชนะ)
    // payToFreelancer = true (จ่ายให้ฟรีแลนซ์), false (คืนเงินให้ผู้ว่าจ้าง)
    function adminResolveDispute(uint _projectId, bool payToFreelancer) public onlyAdmin {
        Project storage proj = projects[_projectId];
        require(proj.status == Status.Disputed, "Project not in dispute");

        uint amount = proj.amount;
        if (payToFreelancer) {
            proj.status = Status.Completed;
            proj.freelancer.transfer(amount);
            emit DisputeResolved(_projectId, "Freelancer Won");
            emit Completed(_projectId, amount);
        } else {
            proj.status = Status.Refunded;
            proj.employer.transfer(amount);
            emit DisputeResolved(_projectId, "Employer Won (Refunded)");
            emit Refunded(_projectId, amount);
        }
    }
}