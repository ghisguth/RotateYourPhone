This document provides instructions for agents and developers working on the RotateYourPhone project.

## Project Overview

RotateYourPhone is a Bash script that processes videos for social media. It rotates, resizes, and prepends a custom intro video, then encodes the result to HEVC (x265) 10-bit format.

## Key Files

- `rotate-your-phone.sh`: The main script.
- `tests/run-tests.sh`: The test suite for the script.
- `media/RotateYourPhoneHD.mp4`: The intro video.

## Development Workflow

When making changes to the script, please follow this workflow:

1.  **Run the tests:** Before making any changes, run the test suite to ensure everything is working as expected.

    ```bash
    cd tests
    ./run-tests.sh --sanity-check
    ```

2.  **Make your changes:** Modify the script as needed.

3.  **Run the tests again:** After making your changes, run the test suite again to ensure you haven't introduced any regressions.

    ```bash
    cd tests
    ./run-tests.sh --run-all
    ```

4.  **Update test data:** If your changes alter the output of the script, you will need to update the expected test data. To do this, run the test suite with the `--update-test-data` flag.

    ```bash
    cd tests
    ./run-tests.sh --run-all --update-test-data
    ```

5.  **Commit your changes:** Once all tests pass, commit your changes with a descriptive commit message.

## Agent Instructions

When working on this project, please adhere to the following guidelines:

-   Always run the test suite before and after making any changes.
-   If your changes affect the output of the script, update the test data using the `--update-test-data` flag.
-   Do not modify the intro video (`media/RotateYourPhoneHD.mp4`) unless specifically instructed to do so.
