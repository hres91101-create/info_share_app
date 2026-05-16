#!/usr/bin/env python3
"""Force every Android subproject to compileSdk 36.

androidx deps pulled in transitively (androidx.core 1.17, androidx.browser
1.9 via url_launcher, etc.) require compiling against API 36+. Plugins also
hardcode old compileSdk values. Forcing every module to 36 satisfies all of
them. android/ is generated fresh by `flutter create` in CI.

The override must be INSERTED before Flutter's own
`subprojects { project.evaluationDependsOn(":app") }` block — appending at the
end registers the afterEvaluate hook too late ("project is already evaluated").
Idempotent. Handles both Groovy (build.gradle) and Kotlin DSL
(build.gradle.kts).
"""
import os
import sys

MARKER = "ci compileSdk override"

GROOVY_BLOCK = f"""// >>> {MARKER}
subprojects {{
    afterEvaluate {{ proj ->
        if (proj.hasProperty('android')) {{
            proj.android {{
                compileSdkVersion 36
            }}
        }}
    }}
}}
// <<< {MARKER}

"""

KOTLIN_BLOCK = f"""// >>> {MARKER}
subprojects {{
    afterEvaluate {{
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {{
            androidExt.compileSdkVersion(36)
        }}
    }}
}}
// <<< {MARKER}

"""


def main() -> int:
    kotlin = "android/build.gradle.kts"
    groovy = "android/build.gradle"
    if os.path.exists(kotlin):
        path, block = kotlin, KOTLIN_BLOCK
    elif os.path.exists(groovy):
        path, block = groovy, GROOVY_BLOCK
    else:
        print("ERROR: no root android/build.gradle[.kts] found", file=sys.stderr)
        return 1

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if MARKER in content:
        print(f"{path}: override already present, skipping")
        return 0

    idx = content.find("subprojects {")
    if idx == -1:
        # no subprojects block — safe to append
        new = content + "\n" + block
    else:
        new = content[:idx] + block + content[idx:]

    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
    print(f"{path}: inserted compileSdk 36 override before subprojects block")
    return 0


if __name__ == "__main__":
    sys.exit(main())
