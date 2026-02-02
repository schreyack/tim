"""Permission handling for plan execution.

Manages tool access permissions with preset configurations.
"""

from pyplan_ops.models import Plan, PlanPermissions

PERMISSION_PRESETS: dict[str, list[str]] = {
    "read-only": [
        "Read",
        "Glob",
        "Grep",
    ],
    "python-dev": [
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Glob",
        "Grep",
        "Task",
    ],
    "node-dev": [
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Glob",
        "Grep",
        "Task",
    ],
    "full-dev": [
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Glob",
        "Grep",
        "Task",
        "WebFetch",
        "WebSearch",
    ],
}


class PermissionManager:
    """Manages permissions for plan execution."""

    def load_from_plan(self, plan: Plan) -> PlanPermissions:
        """Load and resolve permissions from a plan."""
        permissions = plan.permissions

        # Resolve preset to actual tools
        if permissions.preset and permissions.preset in PERMISSION_PRESETS:
            preset_tools = PERMISSION_PRESETS[permissions.preset]
            # Merge preset with any explicit global tools
            all_tools = set(preset_tools) | set(permissions.global_tools)
            permissions.global_tools = sorted(all_tools)

        return permissions

    def prompt_approval(self, permissions: PlanPermissions) -> bool:
        """Display permissions and prompt for user approval."""
        print("\n=== Plan Permissions ===\n")

        if permissions.preset:
            print(f"Preset: {permissions.preset}")

        print(f"\nGlobal tools: {', '.join(permissions.global_tools) or 'None'}")

        if permissions.phase_tools:
            print("\nPhase-specific tools:")
            for phase_id, tools in sorted(permissions.phase_tools.items()):
                print(f"  Phase {phase_id}: {', '.join(tools)}")

        print("\n========================\n")

        response = input("Approve these permissions? [y/N]: ").strip().lower()
        if response == "y":
            permissions.approved = True
            return True
        return False

    def tools_for_phase(self, permissions: PlanPermissions, phase_id: int) -> list[str]:
        """Get the combined tool list for a specific phase."""
        tools = set(permissions.global_tools)

        if phase_id in permissions.phase_tools:
            tools.update(permissions.phase_tools[phase_id])

        return sorted(tools)

    def get_preset_tools(self, preset_name: str) -> list[str]:
        """Get tools for a named preset."""
        return PERMISSION_PRESETS.get(preset_name, [])
