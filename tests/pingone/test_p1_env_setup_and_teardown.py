import unittest

import p1_test_base


class TestP1EnvSetupAndTeardown(p1_test_base.P1TestBase):
    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()

    def test_population_exists(self):
        pop_id = self.get_id(
            self.cluster_env_endpoints.populations, self.population_name
        )
        self.assertIsNotNone(pop_id)


if __name__ == "__main__":
    unittest.main()
