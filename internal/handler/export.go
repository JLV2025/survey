package handler

import (
	"bytes"
	"fmt"
	"strings"

	"survey/internal/middleware"
	"survey/internal/store"

	"github.com/xuri/excelize/v2"
	"net/http"

	"github.com/go-chi/chi/v5"
)

// ExportExcel 导出 Excel
func ExportExcel(w http.ResponseWriter, r *http.Request) {
	username := middleware.GetUsername(r)
	if !store.IsAdmin(username) {
		writeJSON(w, 403, errResp("无权限"))
		return
	}
	surveyID := chi.URLParam(r, "id")
	survey, _ := store.GetSurvey(surveyID)
	if survey == nil {
		writeJSON(w, 404, errResp("问卷不存在"))
		return
	}

	questions := store.GetQuestions(surveyID)
	submissions := store.GetSubmissions(surveyID)

	f := excelize.NewFile()
	defer f.Close()

	// Sheet 1: 原始数据
	f.SetSheetName("Sheet1", "原始数据")
	// 表头
	headers := []string{"序号", "提交时间"}
	if !survey.IsAnonymous {
		headers = append(headers, "用户名")
	}
	for _, q := range questions {
		headers = append(headers, q.Title)
	}

	for i, h := range headers {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		f.SetCellValue("原始数据", cell, h)
	}

	// 数据行
	for rowIdx, sub := range submissions {
		row := rowIdx + 2
		col := 1
		cell, _ := excelize.CoordinatesToCellName(col, row)
		f.SetCellValue("原始数据", cell, rowIdx+1)
		col++
		cell, _ = excelize.CoordinatesToCellName(col, row)
		f.SetCellValue("原始数据", cell, sub.SubmittedAt.Format("2006-01-02 15:04:05"))
		col++

		if !survey.IsAnonymous {
			cell, _ = excelize.CoordinatesToCellName(col, row)
			f.SetCellValue("原始数据", cell, sub.Username)
			col++
		}

		// 构建答案映射
		answerMap := make(map[string]string)
		for _, a := range sub.Answers {
			answerMap[a.QuestionID] = a.Content
		}

		for _, q := range questions {
			content := answerMap[q.ID]
			if q.Type == "single" {
				// 单选题，ID → 选项文本
				for _, o := range q.Options {
					if content == o.ID {
						content = o.Content
						break
					}
				}
			} else if q.Type == "multiple" {
				// 多选题，逗号分隔的 ID → 选项文本
				parts := strings.Split(content, ",")
				var texts []string
				for _, p := range parts {
					p = strings.TrimSpace(p)
					for _, o := range q.Options {
						if p == o.ID {
							texts = append(texts, o.Content)
							break
						}
					}
				}
				content = strings.Join(texts, "；")
			}
			cell, _ = excelize.CoordinatesToCellName(col, row)
			f.SetCellValue("原始数据", cell, content)
			col++
		}
	}

	// Sheet 2: 统计汇总
	_, _ = f.NewSheet("统计汇总")
	row := 1
	cell, _ := excelize.CoordinatesToCellName(1, row)
	f.SetCellValue("统计汇总", cell, fmt.Sprintf("统计汇总 — %s", survey.Title))
	row += 2

	for _, q := range questions {
		cell, _ := excelize.CoordinatesToCellName(1, row)
		f.SetCellValue("统计汇总", cell, q.Title)
		row++

		if q.Type == "single" || q.Type == "multiple" {
			for _, o := range q.Options {
				count := 0
				for _, sub := range submissions {
					for _, a := range sub.Answers {
						if a.QuestionID == q.ID {
							if q.Type == "single" && a.Content == o.ID {
								count++
							} else if q.Type == "multiple" {
								parts := strings.Split(a.Content, ",")
								for _, p := range parts {
									if strings.TrimSpace(p) == o.ID {
										count++
									}
								}
							}
						}
					}
				}
				cell, _ = excelize.CoordinatesToCellName(1, row)
				f.SetCellValue("统计汇总", cell, o.Content)
				cell, _ = excelize.CoordinatesToCellName(2, row)
				f.SetCellValue("统计汇总", cell, count)
				row++
			}
		} else {
			for _, sub := range submissions {
				for _, a := range sub.Answers {
					if a.QuestionID == q.ID && a.Content != "" {
						cell, _ = excelize.CoordinatesToCellName(1, row)
						f.SetCellValue("统计汇总", cell, a.Content)
						row++
					}
				}
			}
		}
		row++
	}

	// 写入 buffer
	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil {
		writeJSON(w, 500, errResp("导出失败"))
		return
	}

	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"survey_%s.xlsx\"", survey.Title))
	w.WriteHeader(200)
	w.Write(buf.Bytes())
}
