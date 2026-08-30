import pathlib
import re
import unittest

from werkzeug.security import check_password_hash

from app import create_app


ROOT = pathlib.Path(__file__).resolve().parents[1]


class StaticProjectTests(unittest.TestCase):
    def test_all_templates_compile(self):
        app = create_app()
        template_names = [path.relative_to(ROOT / "templates").as_posix() for path in (ROOT / "templates").rglob("*.html")]
        for template_name in template_names:
            app.jinja_env.get_template(template_name)

    def test_seeded_demo_credentials_are_valid(self):
        seed_text = (ROOT / "database" / "seed.sql").read_text(encoding="utf-8")
        hashes = re.findall(r"'(scrypt:[^']+)'", seed_text)
        self.assertEqual(2, len(hashes))
        self.assertTrue(check_password_hash(hashes[0], "Admin@123"))
        self.assertTrue(check_password_hash(hashes[1], "Demo@123"))

    def test_required_database_objects_are_declared(self):
        schema_text = (ROOT / "database" / "schema.sql").read_text(encoding="utf-8")
        routine_text = (ROOT / "database" / "routines.sql").read_text(encoding="utf-8")
        for name in ("v_train_schedule_search", "v_daily_sales", "trg_orders_after_update", "trg_order_passengers_before_insert"):
            self.assertIn(name, schema_text)
        for name in ("sp_create_order", "sp_cancel_order", "FOR UPDATE"):
            self.assertIn(name, routine_text)


if __name__ == "__main__":
    unittest.main()
