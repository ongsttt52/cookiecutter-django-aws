export default function Home() {
  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-8">
      <main className="max-w-2xl w-full text-center space-y-8">
        <h1 className="text-4xl font-bold text-gray-900">
          {{cookiecutter.project_name}}
        </h1>
        <p className="text-lg text-gray-600">
          Django REST API + Next.js Frontend
        </p>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-8">
          <a
            href="/api/admin/"
            className="block p-6 bg-white rounded-lg shadow hover:shadow-md transition-shadow"
          >
            <h2 className="text-xl font-semibold text-gray-800">
              Django Admin
            </h2>
            <p className="mt-2 text-sm text-gray-500">
              /api/admin/
            </p>
          </a>

          <a
            href="/api/docs/"
            className="block p-6 bg-white rounded-lg shadow hover:shadow-md transition-shadow"
          >
            <h2 className="text-xl font-semibold text-gray-800">
              API Docs (Swagger)
            </h2>
            <p className="mt-2 text-sm text-gray-500">
              /api/docs/
            </p>
          </a>
        </div>

        <p className="text-sm text-gray-400 mt-12">
          Powered by Next.js 15 + Django 5 + AWS ECS Fargate
        </p>
      </main>
    </div>
  );
}
