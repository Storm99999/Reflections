--!nolint UninitializedLocal
--!nolint UnbalancedAssignment

local Players: Players = game:GetService("Players")
local RunService: RunService = game:GetService("RunService")
local Workspace: Workspace = game:GetService("Workspace")

local Player: Player = Players.LocalPlayer
local ReflectionModel: Model = Workspace:WaitForChild("ReflectionModel") :: Model

local YOffset: number = -0.11
local RayDistance: number = 500

local Character: Model?
local SourceRoot: BasePart?
local ReflectionRoot: BasePart?
local Humanoid: Humanoid?

local SourceMotors: {[string]: Motor6D} = {}
local ReflectionMotors: {[string]: Motor6D} = {}

local LastPlaneY: number = 0
local LastDescendantCount: number = 0

local RayParams: RaycastParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = false
RayParams.RespectCanCollide = true

local function GetRelativePath(Inst: Instance, Ancestor: Instance): string
	if Inst == Ancestor then return "" end
	
	local Path: {string} = {}
	
	while Inst and Inst ~= Ancestor do
		table.insert(Path, 1, Inst.Name)
		Inst = Inst.Parent
	end
	
	return table.concat(Path, "/")
end

local function ResolvePath(Root: Instance, Path: string): Instance?
	if Path == "" then return Root end
	
	local Current: Instance? = Root
	
	for _, Name in (string.split(Path, "/")) do
		if not Current then return nil end
		
		Current = Current:FindFirstChild(Name)
	end
	
	return Current
end

local function Sync(): nil
	if not Character or not ReflectionModel then return end

	local CurrentDescendants = Character:GetDescendants()
	if #CurrentDescendants == LastDescendantCount then return end
	LastDescendantCount = #CurrentDescendants

	for _, Inst in (CurrentDescendants) do
		if Inst:IsA("BasePart") and not Inst:FindFirstAncestorWhichIsA("Model"):GetAttribute("WeaponModel") then
			local Path = GetRelativePath(Inst, Character)
			local RefPart = ResolvePath(ReflectionModel, Path)
			
			if not RefPart then
				RefPart = Inst:Clone()
				RefPart:ClearAllChildren() --// Don't carry over scripts
				
				local BaseRefPart = RefPart :: BasePart
				BaseRefPart.CanCollide = false
				BaseRefPart.CanTouch = false
				BaseRefPart.CanQuery = false
				BaseRefPart.Massless = true

				local ParentPath = GetRelativePath(Inst.Parent, Character)
				BaseRefPart.Parent = ResolvePath(ReflectionModel, ParentPath) or ReflectionModel
			end
		end
	end

	SourceMotors = {}
	
	for _, Inst in (CurrentDescendants) do
		if Inst:IsA("Motor6D") then
			local Path = GetRelativePath(Inst, Character)
			SourceMotors[Path] = Inst

			local RefMotor = ResolvePath(ReflectionModel, Path) :: Motor6D?
			if not RefMotor then
				RefMotor = Inst:Clone() :: Motor6D
				
				local ParentPath = GetRelativePath(Inst.Parent, Character)
				RefMotor.Parent = ResolvePath(ReflectionModel, ParentPath) or ReflectionModel

				if Inst.Part0 then
					RefMotor.Part0 = ResolvePath(ReflectionModel, GetRelativePath(Inst.Part0, Character)) :: BasePart?
				end
				if Inst.Part1 then
					RefMotor.Part1 = ResolvePath(ReflectionModel, GetRelativePath(Inst.Part1, Character)) :: BasePart?
				end
			end
			
			ReflectionMotors[Path] = RefMotor
		end
	end
end

local function Setup(): nil
	SourceMotors = {}
	ReflectionMotors = {}
	LastDescendantCount = 0

	SourceRoot = Character:WaitForChild("HumanoidRootPart") :: BasePart
	ReflectionRoot = ReflectionModel:WaitForChild("HumanoidRootPart") :: BasePart
	Humanoid = Character:WaitForChild("Humanoid") :: Humanoid

	Sync()
end

local function OnCharacterAdded(Char: Model): nil
	Character = Char
	Setup()
end

Player.CharacterAdded:Connect(OnCharacterAdded)

if Player.Character then
	OnCharacterAdded(Player.Character)
end

local function Filter(): nil
	RayParams.FilterDescendantsInstances = {Character, ReflectionModel}
end

local function MirrorC0(CF: CFrame): CFrame
	local Pos = CF.Position
	local RX, RY, RZ = CF:ToOrientation() :: (number, number, number) -> (CFrame, number, number, number) 

	local MirroredPos: Vector3 = Vector3.new(-Pos.X, Pos.Y, Pos.Z)

	return CFrame.new(MirroredPos) * CFrame.Angles(RX, -RY, -RZ)
end

RunService:BindToRenderStep("MirrorReflection", Enum.RenderPriority.Camera.Value - 1, function()
	if not Character or not ReflectionModel then return end
	if not SourceRoot or not ReflectionRoot then return end
	if not SourceRoot.Parent or not ReflectionRoot.Parent then return end

	Sync()
	Filter()

	local Origin: Vector3 = SourceRoot.Position
	local Result: RaycastResult? = Workspace:Raycast(Origin, Vector3.new(0, -RayDistance, 0), RayParams)

	if Result then
		LastPlaneY = Result.Position.Y + YOffset
	end

	local SrcCFrame: CFrame = SourceRoot.CFrame
	local Pos: Vector3 = SrcCFrame.Position
	local MirroredPos: Vector3 = Vector3.new(Pos.X, 2 * LastPlaneY - Pos.Y, Pos.Z)

	local Right: Vector3 = SrcCFrame.RightVector
	local Up: Vector3 = SrcCFrame.UpVector
	local Back: Vector3 = -SrcCFrame.LookVector

	local RRight: Vector3 = -Vector3.new(Right.X, -Right.Y, Right.Z)
	local RUp: Vector3 = Vector3.new(Up.X, -Up.Y, Up.Z)
	local RBack: Vector3 = Vector3.new(Back.X, -Back.Y, Back.Z)

	local MirroredCFrame: CFrame = CFrame.fromMatrix(MirroredPos, RRight, RUp, RBack)

	local Camera: Camera = Workspace.CurrentCamera
	local IsFirstPerson: boolean = Player.CameraMode == Enum.CameraMode.LockFirstPerson --// I was too lazy

	if IsFirstPerson then
		local LookY: number = Camera.CFrame.LookVector.Y

		if LookY < -0.15 then
			local TiltIntensity: number = math.clamp((math.abs(LookY) - 0.15) / 0.85, 0, 1)
			TiltIntensity = math.pow(TiltIntensity, 1.4)

			local MaxTiltAngle: number = math.rad(70)
			local TiltAngle: number = TiltIntensity * MaxTiltAngle

			local HipHeight: number = 3
			
			if Humanoid then
				if Humanoid.RigType == Enum.HumanoidRigType.R15 then
					HipHeight = Humanoid.HipHeight + (SourceRoot.Size.Y / 2)
				else
					HipHeight = 3
				end
			end

			local Pivot: CFrame = CFrame.new(0, HipHeight, 0)
			local Tilt: CFrame = CFrame.Angles(-TiltAngle, 0, 0)
			
			MirroredCFrame = MirroredCFrame * Pivot * Tilt * Pivot:Inverse()
		end
	end

	ReflectionModel:PivotTo(MirroredCFrame)

	for Path, Motor in SourceMotors do
		local DstMotor: Motor6D? = ReflectionMotors[Path]
		
		if DstMotor and DstMotor:IsA("Motor6D") then
			--// If you use IK you need to change this part to use MirrorC0
			DstMotor.Enabled = Motor.Enabled
			DstMotor.C0 = Motor.C0
			DstMotor.C1 = Motor.C1
			DstMotor.Transform = Motor.Transform
		end
	end
end)
